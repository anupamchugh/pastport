import Foundation
import Testing
@testable import PastportKit

@Suite("Timeline trails and evidence cards")
struct TimelineTrailTests {
    private let base = Date(timeIntervalSince1970: 1_781_438_400) // 14 Jun 2026, 12:00 UTC

    /// A three-day burst (14 to 16 Jun) and, a week earlier, one photo and one screenshot.
    private var events: [PhotoEvent] {
        PhotoEvents.cluster([
            PhotoRecord(time: base, isScreenshot: false, labels: ["beach", "sky"]),
            PhotoRecord(time: base.addingTimeInterval(86_400), isScreenshot: false, labels: ["beach"]),
            PhotoRecord(time: base.addingTimeInterval(2 * 86_400), isScreenshot: true, labels: []),
            PhotoRecord(time: base.addingTimeInterval(-7 * 86_400), isScreenshot: false, labels: ["food"]),
            PhotoRecord(time: base.addingTimeInterval(-7 * 86_400 + 60), isScreenshot: true, labels: []),
        ])
    }

    private func shot(_ lines: [String], at offset: TimeInterval = 0) -> AddedScreenshot {
        AddedScreenshot(name: "Shot", addedAt: base.addingTimeInterval(offset), evidence: ScreenshotScrubber.scrub(lines))
    }

    private func cards(_ trail: TimelineTrail, _ shots: [AddedScreenshot] = []) -> [EvidenceCard] {
        EvidenceCards.cards(for: trail, photoEvents: events, screenshots: shots, window: "last 30 days")
    }

    @Test func photosTrailHasOneCardPerEventNewestFirst() {
        let photos = cards(.photos)
        #expect(photos.count == 2)
        #expect(photos.allSatisfy { $0.source == .photoActivity })
        #expect(photos.first?.sentence.hasPrefix("Photos on 3 days") == true)
        #expect(photos.last?.sentence.hasPrefix("1 photo and 1 screenshot on") == true)
        #expect(photos.first?.disclosure.contains("Cleared when you lock or leave the app.") == true)
    }

    @Test func cardNumbersComeFromTheData() throws {
        let burst = try #require(events.first { $0.photoCount == 2 })
        let card = EvidenceCards.photoCard(burst, window: "last 30 days")
        #expect(card.details == ["\(burst.photoCount) photos", "\(burst.screenshotCount) screenshot", "3 days"])
        #expect(card.labels == burst.labels)
    }

    @Test func travelShowsDatesAndCountsAndNoPlaceWord() throws {
        let travel = cards(.travel)
        let card = try #require(travel.first)
        #expect(travel.count == 1, "only the multi-day burst is travel-shaped")
        #expect(card.sentence.contains("3 days"))
        #expect(card.sentence.contains(EvidenceCards.day(base)))
        for word in ["trip to", "near", "in ", "at "] {
            #expect(!card.sentence.lowercased().contains(word), "\(word)")
        }
    }

    @Test func privacyCountsRedactionsByKindAndNeverTheText() throws {
        let privacy = cards(.privacy, [shot(["Mail alice@example.test", "OTP 482913"]), shot(["Gate 4"], at: 60)])
        let summary = try #require(privacy.first)
        #expect(summary.sentence == "2 details hidden in 2 screenshots you added.")
        #expect(summary.details == ["1 email address", "1 one-time code"])
        #expect(privacy.count == 3)
        let all = privacy.map { $0.sentence + $0.details.joined() + $0.disclosure }.joined()
        #expect(!all.contains("alice") && !all.contains("482913"))
        #expect(cards(.privacy, [shot(["Gate 4"])]).first?.sentence == "Nothing sensitive found in 1 screenshot you added.")
        #expect(cards(.privacy).isEmpty)
    }

    @Test func overviewTakesTheNewestFromEachTrailAndAtMostFive() {
        let shots = (0..<6).map { shot(["Note \($0)"], at: Double($0) * 60) }
        let overview = cards(.overview, shots)
        #expect(overview.count == 5)
        #expect(Set(overview.map(\.id)).count == overview.count)
        #expect(overview.contains { $0.source == .photoActivity })
        #expect(overview.contains { $0.id == "privacy-summary" })
    }

    // MARK: Slice 7

    @Test func everyTrailHasAskChips() {
        for trail in TimelineTrail.allCases { #expect(!trail.askChips.isEmpty, "\(trail)") }
    }
}
