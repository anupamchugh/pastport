import Foundation

/// One card on a trail: a source label, one human sentence, the facts behind it, and the
/// "How do we know this?" text. Built by code from the evidence; a model never writes one.
public struct EvidenceCard: Identifiable, Equatable, Sendable {
    public enum Source: String, Sendable {
        case photoActivity = "PHOTO ACTIVITY"
        case screenshot = "SCREENSHOT YOU ADDED"
    }

    public let id: String
    public let source: Source
    public let sentence: String
    /// Facts formatted from data, such as "14 photos" or "3 days".
    public let details: [String]
    /// Scene labels or other words shown under the facts. Never a place.
    public let labels: [String]
    public let disclosure: String
    /// Used to order cards newest first.
    public let date: Date
}

public enum EvidenceCards {
    static let cleared = "Cleared when you lock or leave the app."

    public static func cards(for trail: TimelineTrail, photoEvents: [PhotoEvent], screenshots: [AddedScreenshot],
                             window: String) -> [EvidenceCard] {
        switch trail {
        case .photos:
            return newestFirst(photoEvents.map { photoCard($0, window: window) })
        case .travel:
            let multiDay = photoEvents.filter { dayCount($0) > 1 }.map { photoCard($0, window: window) }
            let bookings = screenshots.compactMap { bookingCard($0) }
            return newestFirst(multiDay + bookings)
        case .privacy:
            guard !screenshots.isEmpty else { return [] }
            return [privacySummary(screenshots)] + newestFirst(screenshots.map(screenshotCard))
        case .overview:
            let others: [TimelineTrail] = [.travel, .photos, .privacy]
            var chosen: [EvidenceCard] = []
            for other in others {
                if let newest = cards(for: other, photoEvents: photoEvents, screenshots: screenshots, window: window)
                    .first(where: { card in !chosen.contains { $0.id == card.id } }) {
                    chosen.append(newest)
                }
            }
            let rest = newestFirst(others.flatMap {
                cards(for: $0, photoEvents: photoEvents, screenshots: screenshots, window: window)
            })
            for card in rest where chosen.count < 5 && !chosen.contains(where: { $0.id == card.id }) {
                chosen.append(card)
            }
            return Array(chosen.prefix(5))
        }
    }

    // MARK: Cards

    static func photoCard(_ event: PhotoEvent, window: String) -> EvidenceCard {
        let days = dayCount(event)
        let start = day(event.start), end = day(event.end)
        let sentence: String
        if days > 1 {
            sentence = "Photos on \(days) days, \(start) to \(end)."
        } else if event.screenshotCount > 0, event.photoCount > 0 {
            sentence = "\(count(event.photoCount, "photo")) and \(count(event.screenshotCount, "screenshot")) on \(start)."
        } else if event.photoCount > 0 {
            sentence = "\(count(event.photoCount, "photo")) on \(start)."
        } else {
            sentence = "\(count(event.screenshotCount, "screenshot")) on \(start)."
        }
        var details = [count(event.photoCount, "photo"), count(event.screenshotCount, "screenshot")]
        if days > 1 { details.append(count(days, "day")) }
        return EvidenceCard(
            id: "photo-\(Int(event.start.timeIntervalSince1970))",
            source: .photoActivity, sentence: sentence, details: details,
            labels: Array(event.labels.prefix(5)),
            disclosure: "Read: photo dates and counts in the \(window), and scene labels checked on this iPhone. "
                + "Screenshots are counted only. \(cleared)",
            date: event.end)
    }

    static func bookingCard(_ shot: AddedScreenshot) -> EvidenceCard? {
        guard let booking = BookingFromScreenshot.detect(shot.evidence) else { return nil }
        let kind = title(for: booking.kind)
        let when = day(booking.date)
        let sentence = booking.title.isEmpty ? "\(kind) dated \(when)." : "\(kind) dated \(when): \(booking.title)."
        return EvidenceCard(
            id: "booking-\(shot.id.uuidString)", source: .screenshot, sentence: sentence, details: [kind, when],
            labels: [],
            disclosure: "Read: the text of a screenshot you added, with emails, codes and card numbers hidden first. "
                + "A screenshot does not prove the trip happened. \(cleared)",
            date: booking.date)
    }

    static func screenshotCard(_ shot: AddedScreenshot) -> EvidenceCard {
        let kind = shot.evidence.kind == .unknown ? "Screenshot" : shot.evidence.kind.title + " screenshot"
        let hidden = shot.evidence.redactionCount
        let sentence = hidden == 0 ? "\(kind), nothing sensitive found." : "\(kind), \(count(hidden, "detail")) hidden."
        return EvidenceCard(
            id: "shot-\(shot.id.uuidString)", source: .screenshot, sentence: sentence,
            details: redactionDetails(shot.evidence.redactions), labels: [],
            disclosure: "Read: the text of this screenshot on this iPhone. The image is not kept. \(cleared)",
            date: shot.addedAt)
    }

    static func privacySummary(_ shots: [AddedScreenshot]) -> EvidenceCard {
        let total = shots.map(\.evidence.redactions).reduce(RedactionCounts.zero, +)
        let added = count(shots.count, "screenshot")
        let sentence = total.total == 0
            ? "Nothing sensitive found in \(added) you added."
            : "\(count(total.total, "detail")) hidden in \(added) you added."
        return EvidenceCard(
            id: "privacy-summary", source: .screenshot, sentence: sentence, details: redactionDetails(total), labels: [],
            disclosure: "Emails, one-time codes and card numbers are replaced before you see the text. "
                + "Only the counts are kept, never the hidden text. \(cleared)",
            date: shots.map(\.addedAt).max() ?? .distantPast)
    }

    /// Per-kind counts, kind only, such as "2 email addresses". Empty kinds are left out.
    public static func redactionDetails(_ counts: RedactionCounts) -> [String] {
        var details: [String] = []
        if counts.email > 0 { details.append(count(counts.email, "email address", "email addresses")) }
        if counts.otp > 0 { details.append(count(counts.otp, "one-time code")) }
        if counts.card > 0 { details.append(count(counts.card, "card number")) }
        return details
    }

    public static func title(for kind: Booking.Kind) -> String {
        switch kind {
        case .ticket: "Ticket"
        case .confirmation: "Confirmation"
        case .itinerary: "Itinerary"
        case .checkout: "Checkout"
        }
    }

    // MARK: Formatting

    static func count(_ n: Int, _ one: String, _ many: String? = nil) -> String {
        "\(n) \(n == 1 ? one : many ?? one + "s")"
    }

    static func dayCount(_ event: PhotoEvent) -> Int {
        let calendar = Calendar.current
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: event.start),
                                           to: calendar.startOfDay(for: event.end)).day ?? 0
        return days + 1
    }

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("dMMM")
        return formatter
    }()

    static func day(_ date: Date) -> String { dayFormatter.string(from: date) }

    private static func newestFirst(_ cards: [EvidenceCard]) -> [EvidenceCard] {
        cards.sorted { $0.date > $1.date }
    }
}
