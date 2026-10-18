import Foundation
import Testing
@testable import PastportKit

@Suite("History journey policy")
struct HistoryJourneyTests {
    @Test("Focus suggestions require matching evidence")
    func focusSelectionUsesEvidence() {
        #expect(
            HistoryJourneyValidation.supportedFocuses(
                hasResearch: false,
                hasBookings: false,
                hasLocationEvidence: false,
                hasNamedPlace: false
            ) == [.overview]
        )

        #expect(
            HistoryJourneyValidation.supportedFocuses(
                hasResearch: true,
                hasBookings: true,
                hasLocationEvidence: true,
                hasNamedPlace: true
            ) == [.overview, .research, .travel, .privacy, .places]
        )
    }

    @Test("Context policy compacts before the bounded window")
    func contextCompactionThreshold() {
        #expect(!HistoryJourneyContextPolicy.shouldCompact(tokenCount: 2_399, budget: 3_200))
        #expect(HistoryJourneyContextPolicy.shouldCompact(tokenCount: 2_400, budget: 3_200))
        #expect(HistoryJourneyContextPolicy.shouldCompact(tokenCount: 1, budget: 0))
    }

    @Test("Grounding rejects unsupported counts and completed booking claims")
    func staleFactsAreGuarded() {
        let packet = [
            "visits: 4 retained visits",
            "window: 2026-10-01 to 2026-10-02",
            "booking-like pages: 1 page signal"
        ]
        #expect(HistoryJourneyValidation.allowsNarrative("There were 4 retained visits.", evidenceLines: packet))
        #expect(!HistoryJourneyValidation.allowsNarrative("You booked the trip and paid 99.", evidenceLines: packet))
        #expect(!HistoryJourneyValidation.allowsNarrative("There were 12 retained visits.", evidenceLines: packet))
        #expect(!HistoryJourneyValidation.allowsNarrative("A matching visit confirms a booking titled Demo Stay.", evidenceLines: packet))
        #expect(!HistoryJourneyValidation.allowsNarrative("There were 126828 visits.", evidenceLines: ["visits: 126,882 retained visits"]))
        #expect(HistoryJourneyValidation.allowsNarrative("There were 126,882 visits.", evidenceLines: ["visits: 126882 retained visits"]))
        #expect(HistoryJourneyValidation.allowsNarrative("A history page does not confirm a purchase.", evidenceLines: packet))
    }

    @Test("an overview request is not redirected by a negated trip warning")
    func overviewIntentPrecedesIncidentalTopics() {
        #expect(JourneyEvidence.inferredFocus(for: "Summarize all retained history and research. Do not infer trips.", visits: []) == .overview)
        #expect(JourneyEvidence.inferredFocus(for: "Which booking-like pages appear?", visits: []) == .travel)
    }

    @Test("cached detector evidence still recomputes each question's matching visits")
    func cachedEvidenceDoesNotReuseQuestionMatches() {
        let visits = [
            Visit(time: Date(timeIntervalSince1970: 1_750_000_000), title: "amber", url: "https://amber.example"),
            Visit(time: Date(timeIntervalSince1970: 1_750_000_001), title: "azure", url: "https://azure.example")
        ]
        let first = JourneyEvidence.make(visits: visits, question: "amber", focus: .overview)
        let second = JourneyEvidence.make(visits: visits, question: "azure", focus: .overview, cached: first)
        #expect(first.matches.map(\.title) == ["amber"])
        #expect(second.matches.map(\.title) == ["azure"])
        #expect(second.stats.total == 2)
    }

    @Test("same-size changed windows cannot reuse detector evidence or model context")
    func cacheRequiresExactVisits() {
        let a = Visit(time: .now, title: "first", url: "https://first.example")
        let b = Visit(time: .now, title: "second", url: "https://second.example")
        let previous = HistoryQuestionScope(visits: [a], rangeDescription: "last 30 days", matchedWindow: true)
        let same = HistoryQuestionScope(visits: [a], rangeDescription: "last 30 days", matchedWindow: true)
        let changed = HistoryQuestionScope(visits: [b], rangeDescription: "last 30 days", matchedWindow: true)
        #expect(JourneyEvidence.canReuse(previous: previous, resolved: same))
        #expect(!JourneyEvidence.canReuse(previous: previous, resolved: changed))
        #expect(!JourneyEvidence.canReuse(previous: nil, resolved: same))
    }

    @Test("matching evidence remains bounded to the first 24 matching visits")
    func matchingEvidenceIsBounded() {
        let visits = (0..<40).map { Visit(time: .now, title: "match \($0)", url: "https://fixture.example") }
        let evidence = JourneyEvidence.make(visits: visits, question: "match", focus: .overview)
        #expect(evidence.matches.count == 24)
        #expect(evidence.matches.last?.title == "match 23")
        #expect(evidence.visitCount == 40)
    }

    @Test("Public contract keeps focus identity and receipt state explicit")
    func publicContract() {
        #expect(HistoryFocus.allCases.map(\.id) == ["overview", "research", "travel", "privacy", "places"])
        #expect(HistoryFocus.travel.title == "Travel and bookings")
        let receipt = JourneyReceipt(
            sessionID: UUID(), turn: 2, mode: "travel", toolCalls: ["find_bookings"],
            toolOutputCount: 1, inputTokens: nil, outputTokens: nil, contextTokens: 40,
            contextTokenMeasurement: "estimated", seconds: 0.2,
            usedDynamicProfile: false, didCompact: true,
            summary: "grounded"
        )
        #expect(receipt.didCompact)
        #expect(receipt.summary == "grounded")
    }
}
