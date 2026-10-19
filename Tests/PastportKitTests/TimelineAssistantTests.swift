import Foundation
import Testing
@testable import PastportKit

@Suite("Timeline evidence and answer policy")
struct TimelineAssistantTests {
    private let day = Date(timeIntervalSince1970: 1_751_328_000)

    private func evidence(screenshots: [AddedScreenshot] = []) -> TimelineEvidence {
        let events = PhotoEvents.cluster([
            PhotoRecord(time: day, isScreenshot: false, labels: ["beach"]),
            PhotoRecord(time: day.addingTimeInterval(60), isScreenshot: false, labels: ["beach"]),
            PhotoRecord(time: day.addingTimeInterval(120), isScreenshot: true, labels: []),
        ])
        return TimelineEvidence(window: "last 30 days", photoEvents: events,
                                screenshots: screenshots, historyAvailable: false)
    }

    @Test func deterministicSummaryPassesItsOwnNumberCheck() {
        let shot = AddedScreenshot(name: "Booking", evidence: ScreenshotScrubber.scrub(["Booking confirmed", "Ref 4821"]))
        let facts = evidence(screenshots: [shot])
        #expect(facts.deterministicSummary.contains("2 photos"))
        #expect(TimelineAnswerPolicy.allows(facts.deterministicSummary, evidence: facts))
    }

    @Test func rejectsAnswerWithNumberNotInEvidence() {
        let facts = evidence()
        #expect(!TimelineAnswerPolicy.allows("You took 40 photos at the beach.", evidence: facts))
        #expect(TimelineAnswerPolicy.allows("You took 2 photos at the beach.", evidence: facts))
    }

    @Test func rejectsCompletedBookingClaimFromScreenshot() {
        let shot = AddedScreenshot(name: "Booking", evidence: ScreenshotScrubber.scrub(["Hotel Demo", "Checkout"]))
        #expect(!TimelineAnswerPolicy.allows("You booked Hotel Demo.", evidence: evidence(screenshots: [shot])))
    }

    @Test func modelSeesOnlyScrubbedScreenshotText() {
        let shot = AddedScreenshot(name: "Receipt", evidence: ScreenshotScrubber.scrub([
            "Sent to guest@example.com", "Code 482913", "Card 4111 1111 1111 1111",
        ]))
        let packet = evidence(screenshots: [shot]).lines.joined(separator: "\n")
        #expect(!packet.contains("guest@example.com"))
        #expect(!packet.contains("4111 1111 1111 1111"))
        #expect(packet.contains("[EMAIL]") && packet.contains("[CARD]"))
    }

    @Test func photoDatesAreReadableAndCitable() {
        let facts = evidence()
        let line = facts.photoLines.joined()
        let date = day.formatted(date: .abbreviated, time: .omitted)
        #expect(line.contains(date))
        #expect(TimelineAnswerPolicy.allows("Photos from \(date) show a beach.", evidence: facts))
    }

    @Test func emptyTimelineSaysWhatToDoAndThatSafariIsNotReadable() {
        let empty = TimelineEvidence(window: "last 7 days", photoEvents: [], screenshots: [], historyAvailable: false)
        #expect(empty.isEmpty)
        #expect(empty.deterministicSummary.contains("Read photo activity or add a screenshot"))
        #expect(empty.deterministicSummary.contains("Safari history is not readable on this device"))
        #expect(empty.countsLine.contains("Safari history not readable on this device"))
    }
    @Test func failingFinalTextIsReplacedEvenAfterAPassingPartial() {
        let facts = evidence()
        // "You took 2 photos on" passed and was shown; the finished text adds an unsupported date.
        let final = TimelineAnswerPolicy.finalProgress(raw: "You took 2 photos on 5 July.", shown: "You took 2 photos on",
                                                       toolsUsed: ["photo_activity"], evidence: facts)
        #expect(final?.text == facts.deterministicSummary)
        #expect(final?.toolsUsed == ["photo_activity"])
        guard case .facts = final?.source else { Issue.record("expected the facts fallback"); return }
    }

    @Test func passingFinalTextIsShownOnce() {
        let facts = evidence()
        let same = TimelineAnswerPolicy.finalProgress(raw: "You took 2 photos.", shown: "You took 2 photos.",
                                                      toolsUsed: [], evidence: facts)
        #expect(same == nil)
        let longer = TimelineAnswerPolicy.finalProgress(raw: "You took 2 photos.", shown: "You took",
                                                        toolsUsed: [], evidence: facts)
        #expect(longer == TimelineAnswerProgress(text: "You took 2 photos.", source: .model))
    }

    @Test func emptyFinalTextFallsBackToFacts() {
        let facts = evidence()
        let final = TimelineAnswerPolicy.finalProgress(raw: "", shown: "", toolsUsed: [], evidence: facts)
        #expect(final?.text == facts.deterministicSummary)
    }
}
