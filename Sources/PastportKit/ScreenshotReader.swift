import Foundation
import Vision

/// The minimum classification needed before screenshot text can reach a model.
/// Classification uses sanitized OCR only; raw OCR never leaves `read(imageAt:)`.
public enum ScreenshotKind: String, Equatable, Sendable {
    case chat
    case banking
    case receipt
    case unknown

    /// Sensitive screenshot kinds require an explicit caller opt-in for narration.
    public var title: String {
        switch self {
        case .chat: "Chat"
        case .banking: "Banking"
        case .receipt: "Receipt"
        case .unknown: "Other"
        }
    }

    public var requiresNarrationOptIn: Bool {
        switch self {
        case .chat, .banking, .receipt, .unknown: return true
        }
    }
}

/// How many items of each kind were hidden in one screenshot. Counts only; never the text.
public struct RedactionCounts: Equatable, Sendable {
    public var email: Int
    public var otp: Int
    public var card: Int

    public init(email: Int = 0, otp: Int = 0, card: Int = 0) {
        self.email = email
        self.otp = otp
        self.card = card
    }

    public static let zero = RedactionCounts()

    public var total: Int { email + otp + card }

    public static func + (lhs: RedactionCounts, rhs: RedactionCounts) -> RedactionCounts {
        RedactionCounts(email: lhs.email + rhs.email, otp: lhs.otp + rhs.otp, card: lhs.card + rhs.card)
    }
}

/// OCR evidence that is safe to hand to later deterministic or model-backed stages.
///
/// Raw recognized text is deliberately not representable by this type.
public struct ScreenshotEvidence: Equatable, Sendable {
    let lines: [String]
    public let redactions: RedactionCounts
    public let kind: ScreenshotKind

    public var redactionCount: Int { redactions.total }

    /// Recognized text after emails, one-time codes and card numbers were replaced.
    public var scrubbedLines: [String] { lines }

    var text: String { lines.joined(separator: "\n") }

    init(lines: [String], redactions: RedactionCounts, kind: ScreenshotKind) {
        self.lines = lines
        self.redactions = redactions
        self.kind = kind
    }

    /// The only text-shaped value intended for a narration prompt.
    /// Chat, banking, and receipt screenshots stay excluded by default.
    public func narrationText(allowSensitive: Bool = false) -> String? {
        guard allowSensitive || !kind.requiresNarrationOptIn else { return nil }
        return text.isEmpty ? nil : text
    }
}

public struct ScreenshotReader: Sendable {
    private let recognize: @Sendable (URL) async throws -> [String]

    init(recognize: @escaping @Sendable (URL) async throws -> [String]) {
        self.recognize = recognize
    }

    public init() {
        self.recognize = { url in
            #if compiler(>=6.4)
            if #available(macOS 15.0, *) {
                var request = RecognizeTextRequest()
                request.recognitionLevel = .accurate
                request.automaticallyDetectsLanguage = true
                let observations = try await request.perform(on: url)
                return observations.compactMap { $0.topCandidates(1).first?.string }
            }

            #endif
            return try await Task.detached {
                let request = VNRecognizeTextRequest()
                request.recognitionLevel = .accurate
                request.automaticallyDetectsLanguage = true
                request.usesLanguageCorrection = true
                let handler = VNImageRequestHandler(url: url)
                try handler.perform([request])
                return request.results?.compactMap {
                    $0.topCandidates(1).first?.string
                } ?? []
            }.value
        }
    }

    public func read(imageAt url: URL) async throws -> ScreenshotEvidence {
        ScreenshotScrubber.scrub(try await recognize(url))
    }

    /// Reads picked image data through a short-lived private file that is removed after OCR.
    public func read(imageData: Data) async throws -> ScreenshotEvidence {
        let url = FileManager.default.temporaryDirectory.appending(path: "pastport-shot-\(UUID().uuidString)")
        try imageData.write(to: url, options: [.atomic, .completeFileProtection])
        defer { try? FileManager.default.removeItem(at: url) }
        return try await read(imageAt: url)
    }

    /// Read, gate, and then hand only scrubbed text to a model-facing callback.
    /// The callback is never invoked for sensitive or unclassified screenshots unless
    /// the caller explicitly opts in.
    public func narrate(
        imageAt url: URL,
        allowSensitive: Bool = false,
        using narrate: @Sendable (String) async throws -> String
    ) async throws -> String? {
        let evidence = try await read(imageAt: url)
        guard let text = evidence.narrationText(allowSensitive: allowSensitive) else { return nil }
        return try await narrate(text)
    }
}

enum ScreenshotScrubber {
    private static let email = try! NSRegularExpression(
        pattern: #"[\p{L}\p{N}._%+\-]+\s*@\s*[\p{L}\p{N}\-]+(?:\s*\.\s*[\p{L}\p{N}\-]+)+"#,
        options: [.caseInsensitive]
    )
    private static let otp = try! NSRegularExpression(
        // OCR can emit Greek or Cyrillic look-alikes for the Latin OTP label.
        pattern: #"\b(?:[OОΟ][TТΤ][PРΡ]|one(?:[\s\p{Pd}-]*)time(?:[\s\p{Pd}-]+password)?(?:\s*\(\s*OTP\s*\))?|verification\s+code|security\s+code|passcode)(?=\s|:|\p{Pd}|-|$)(?:\s+is)?\s*(?:[:\p{Pd}-]\s*)?[0-9](?:[\s\p{Pd}-]*[0-9]){3,7}(?![\s\p{Pd}-]*[0-9])"#,
        options: [.caseInsensitive]
    )
    private static let card = try! NSRegularExpression(
        pattern: #"(?<![0-9])(?:[0-9](?:[\s\p{Pd}-]*)){12,18}[0-9](?![\s\p{Pd}-]*[0-9])"#,
        options: []
    )

    static func scrub(_ lines: [String]) -> ScreenshotEvidence {
        guard !lines.isEmpty else {
            return ScreenshotEvidence(lines: [], redactions: .zero, kind: .unknown)
        }
        let text = lines.joined(separator: "\n")
        let (withoutEmails, emailCount) = replacing(email, in: text, with: "[EMAIL]")
        let (withoutOTPs, otpCount) = replacing(otp, in: withoutEmails, with: "[OTP]")
        let (sanitized, cardCount) = replacing(card, in: withoutOTPs, with: "[CARD]")
        let sanitizedLines = sanitized.components(separatedBy: "\n")
        return ScreenshotEvidence(
            lines: sanitizedLines,
            redactions: RedactionCounts(email: emailCount, otp: otpCount, card: cardCount),
            kind: ScreenshotKindClassifier.classify(sanitizedLines)
        )
    }

    private static func replacing(
        _ expression: NSRegularExpression,
        in text: String,
        with token: String
    ) -> (String, Int) {
        let range = NSRange(text.startIndex..., in: text)
        let count = expression.numberOfMatches(in: text, range: range)
        let replaced = expression.stringByReplacingMatches(
            in: text,
            range: range,
            withTemplate: token
        )
        return (replaced, count)
    }
}

enum ScreenshotKindClassifier {
    static let bankingMarkers = [
        "bank", "account balance", "available balance", "transaction", "upi",
        "ifsc", "debit", "credit", "statement", "beneficiary", "amount paid"
    ]
    private static let chatMarkers = [
        "whatsapp", "imessage", "messages", "messenger", "telegram", "signal",
        "reply", "typing", "last seen", "online"
    ]
    private static let receiptMarkers = [
        "receipt", "invoice", "order total", "subtotal", "payment successful",
        "confirmation number", "order number", "tax invoice"
    ]

    /// Banking wins when a screenshot is both a chat and a banking screen, as in a
    /// family banking conversation. The caller therefore gets the stricter label.
    /// Precedence: banking, chat, booking, receipt. A dated ticket whose only banking marker
    /// is "amount paid" is not banking, so it can become a booking.
    static func classify(_ lines: [String]) -> ScreenshotKind {
        let text = lines.joined(separator: " ").lowercased()
        if bankingMarkers.contains(where: text.contains), !BookingFromScreenshot.outranksBanking(lines) { return .banking }
        if chatMarkers.contains(where: text.contains) { return .chat }
        if receiptMarkers.contains(where: text.contains) { return .receipt }
        return .unknown
    }
}
