import Foundation

/// A booking read from a screenshot the person added: a ticket or a confirmation with a date.
/// Derived from scrubbed text only; `ScreenshotKind` gains no case for it.
public struct BookingFromScreenshot: Sendable, Equatable {
    public let kind: Booking.Kind
    public let date: Date
    /// The first line of the screenshot, such as the operator or the stay.
    public let title: String

    public init(kind: Booking.Kind, date: Date, title: String) {
        self.kind = kind
        self.date = date
        self.title = title
    }

    /// A booking needs a ticket marker and a date. Chat and banking screens never make one.
    public static func detect(_ evidence: ScreenshotEvidence) -> BookingFromScreenshot? {
        guard evidence.kind != .chat, evidence.kind != .banking else { return nil }
        return detect(lines: evidence.scrubbedLines)
    }

    static func detect(lines: [String]) -> BookingFromScreenshot? {
        let text = lines.joined(separator: " ")
        let lowered = text.lowercased()
        guard let kind = kind(in: lowered), !hasStrictBankingMarker(lowered), let date = firstDate(in: text) else { return nil }
        let title = lines.lazy.map { $0.trimmingCharacters(in: .whitespaces) }
            .first { $0.contains(where: \.isLetter) } ?? ""
        return BookingFromScreenshot(kind: kind, date: date, title: String(title.prefix(60)))
    }

    /// True when the booking check runs before the banking check: a ticket marker and a date,
    /// and no banking marker other than "amount paid".
    static func outranksBanking(_ lines: [String]) -> Bool {
        let text = lines.joined(separator: " ")
        let lowered = text.lowercased()
        return kind(in: lowered) != nil && !hasStrictBankingMarker(lowered) && firstDate(in: text) != nil
    }

    private static let ticketMarkers = ["boarding pass", "e-ticket", "eticket", "e ticket"]
    private static let stayMarkers = ["check-in", "check in"]

    private static func kind(in lowered: String) -> Booking.Kind? {
        if ticketMarkers.contains(where: lowered.contains) || Bookings.containsWord(anyOf: ["pnr"], in: lowered) {
            return .ticket
        }
        if stayMarkers.contains(where: lowered.contains) { return .confirmation }
        return nil
    }

    private static func hasStrictBankingMarker(_ lowered: String) -> Bool {
        ScreenshotKindClassifier.bankingMarkers.filter { $0 != "amount paid" }.contains(where: lowered.contains)
    }

    private static let dateDetector = try! NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue)

    private static func firstDate(in text: String) -> Date? {
        dateDetector.firstMatch(in: text, range: NSRange(text.startIndex..., in: text))?.date
    }
}
