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
