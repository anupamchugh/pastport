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
    public var requiresNarrationOptIn: Bool {
        switch self {
        case .chat, .banking, .receipt, .unknown: return true
        }
    }
}

/// OCR evidence that is safe to hand to later deterministic or model-backed stages.
///
/// Raw recognized text is deliberately not representable by this type.
public struct ScreenshotEvidence: Equatable, Sendable {
    let lines: [String]
    let redactionCount: Int
    public let kind: ScreenshotKind

    var text: String { lines.joined(separator: "\n") }

    init(lines: [String], redactionCount: Int, kind: ScreenshotKind) {
        self.lines = lines
        self.redactionCount = redactionCount
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
            if #available(macOS 15.0, *) {
                var request = RecognizeTextRequest()
                request.recognitionLevel = .accurate
                request.automaticallyDetectsLanguage = true
                let observations = try await request.perform(on: url)
                return observations.compactMap { $0.topCandidates(1).first?.string }
            }

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
        pattern: #"\b(?:OTP|one(?:[\s\p{Pd}-]*)time(?:[\s\p{Pd}-]+password)?(?:\s*\(\s*OTP\s*\))?|verification\s+code|security\s+code|passcode)(?=\s|:|\p{Pd}|-|$)(?:\s+is)?\s*(?:[:\p{Pd}-]\s*)?[0-9](?:[\s\p{Pd}-]*[0-9]){3,7}(?![\s\p{Pd}-]*[0-9])"#,
        options: [.caseInsensitive]
    )
    private static let card = try! NSRegularExpression(
        pattern: #"(?<![0-9])(?:[0-9](?:[\s\p{Pd}-]*)){12,18}[0-9](?![\s\p{Pd}-]*[0-9])"#,
        options: []
    )

    static func scrub(_ lines: [String]) -> ScreenshotEvidence {
        guard !lines.isEmpty else {
            return ScreenshotEvidence(lines: [], redactionCount: 0, kind: .unknown)
        }
        let text = lines.joined(separator: "\n")
        let (withoutEmails, emailCount) = replacing(email, in: text, with: "[EMAIL]")
        let (withoutOTPs, otpCount) = replacing(otp, in: withoutEmails, with: "[OTP]")
        let (sanitized, cardCount) = replacing(card, in: withoutOTPs, with: "[CARD]")
        let sanitizedLines = sanitized.components(separatedBy: "\n")
        return ScreenshotEvidence(
            lines: sanitizedLines,
            redactionCount: emailCount + otpCount + cardCount,
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
    private static let bankingMarkers = [
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
    static func classify(_ lines: [String]) -> ScreenshotKind {
        let text = lines.joined(separator: " ").lowercased()
        if bankingMarkers.contains(where: text.contains) { return .banking }
        if chatMarkers.contains(where: text.contains) { return .chat }
        if receiptMarkers.contains(where: text.contains) { return .receipt }
        return .unknown
    }
}
