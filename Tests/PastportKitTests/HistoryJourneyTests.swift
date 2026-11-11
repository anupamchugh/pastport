import Foundation
import FoundationModels
import Testing
@testable import PastportKit

@Suite("History journey policy")
struct HistoryJourneyTests {
    @Test("dynamic trail schema produces an evidence-supported nested plan",
          .enabled(if: SystemLanguageModel.default.isAvailable, "Needs Apple Intelligence"))
    func dynamicTrailSchemaWithModel() async throws {
        let journey = HistoryJourney(
            visits: [Visit(time: .now, title: "A page", url: "https://example.com/page")],
            scope: "fictional test history"
        )
        let recommendation = try await journey.recommend("Suggest a trail for this history.")
        await journey.clear()
        #expect(recommendation.usedModel, "The dynamic schema must produce a model result, not the fallback")
        #expect(recommendation.focuses == [.overview])
    }
    @Test("trail planning rejects unsupported and duplicate stages")
    func trailPlanUsesOnlySupportedDistinctFocuses() {
        let stages = JourneyPlanner.validatedFocuses(
            ["research", "places", "research", "travel", "overview", "privacy"],
            supported: [.overview, .research, .travel]
        )
        #expect(stages == [.research, .travel, .overview])
    }
    @Test("a site trail matches the exact host, not a URL mentioning it")
    func siteTrailUsesExactHost() {
        let visits = [
            Visit(time: .now, title: "One", url: "https://example.com/one"),
            Visit(time: .now, title: "Other", url: "https://other.com/?next=example.com"),
            Visit(time: .now, title: "Subdomain", url: "https://news.example.com/one")
        ]
        let evidence = JourneyEvidence.make(visits: visits, question: "Which pages did I visit on example.com?", focus: nil)
        #expect(evidence.matches.map(\.title) == ["One"])
    }
    @Test("deterministic fallback is not labelled as a model answer")
    func historyAnswerOrigin() {
        #expect(HistoryAnswer.origin(for: "Recorded facts", deterministicAnswer: "Recorded facts") == .recordedFacts)
        #expect(HistoryAnswer.origin(for: "A grounded summary", deterministicAnswer: "Recorded facts") == .model)
    }
    @Test("matching source cards deduplicate and remove private URL parameters")
    func matchingSourcesAreSafeAndRecent() throws {
        let old = Date(timeIntervalSince1970: 100)
        let recent = Date(timeIntervalSince1970: 200)
        let sources = HistoryPageMatch.matching([
            Visit(time: old, title: "Older", url: "https://example.com/article?utm_source=one#section"),
            Visit(time: recent, title: "Recent", url: "https://example.com/article?utm_source=one#section"),
            Visit(time: old, title: "Same page, different tracking", url: "https://example.com/article?utm_source=other"),
            Visit(time: recent, title: "Local file", url: "file:///tmp/private"),
            Visit(time: recent, title: "Credentials", url: "https://name:password@example.com/secret")
        ])
        #expect(sources.count == 1)
        let source = try #require(sources.first)
        #expect(source.title == "Recent")
        #expect(source.url.absoluteString == "https://example.com/article")
        #expect(source.originalURL.absoluteString == "https://example.com/article?utm_source=one#section")
        #expect(HistoryPageMatch.matching([], limit: 0).isEmpty)
    }
    @Test("different search queries remain distinct despite sanitized display URLs")
    func matchingSourcesPreserveFunctionalQueries() {
        let sources = HistoryPageMatch.matching([
            Visit(time: .now, title: "First search", url: "https://example.com/search?q=first&utm_source=a"),
            Visit(time: .now, title: "Second search", url: "https://example.com/search?q=second&utm_source=b")
        ])
        #expect(sources.count == 2)
    }
    @Test("bounded model work returns at the deadline when cancellation is ignored")
    func boundedTaskDoesNotWaitForNonCooperativeWork() async throws {
        let start = ContinuousClock.now
        await #expect(throws: CLIError.self) {
            try await boundedTask(timeout: .milliseconds(20), operation: {
                await Task.detached { nonCooperativeWork() }.value
            }, onTimeout: {})
        }
        // The blocking work sleeps 2 s; returning well before that proves the deadline, even on a loaded machine.
        #expect(start.duration(to: .now) < .seconds(1))
    }

    @Test("bounded work that finishes in time returns its value and never calls onTimeout")
    func boundedTaskReturnsValueBeforeDeadline() async throws {
        let timeouts = Counter()
        let value = try await boundedTask(timeout: .seconds(5), operation: { 42 }, onTimeout: { timeouts.add() })
        #expect(value == 42)
        try await Task.sleep(for: .milliseconds(50))
        #expect(timeouts.value == 0)
    }

    @Test("bounded work that throws in time rethrows that error")
    func boundedTaskRethrowsOperationError() async {
        struct Boom: Error {}
        await #expect(throws: Boom.self) {
            try await boundedTask(timeout: .seconds(5), operation: { () async throws -> Int in throw Boom() }, onTimeout: {})
        }
    }

    @Test("a deadline runs onTimeout once, before the caller sees the timeout error")
    func boundedTaskCallsOnTimeoutOnceBeforeThrowing() async throws {
        let timeouts = Counter()
        let seenAtThrow = Counter()
        do {
            _ = try await boundedTask(timeout: .milliseconds(20), operation: {
                try await Task.sleep(for: .seconds(30))
                return 1
            }, onTimeout: { timeouts.add() })
            Issue.record("expected a timeout")
        } catch {
            seenAtThrow.set(timeouts.value)
        }
        try await Task.sleep(for: .milliseconds(100))
        #expect(seenAtThrow.value == 1, "onTimeout ran before the error was thrown")
        #expect(timeouts.value == 1)
    }

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
        #expect(HistoryJourneyValidation.renderSection("The trip was booked.", evidenceLines: packet, includeSources: true) == nil,
                "Rejected model text must not become a standalone source line that hides the deterministic fallback")
    }

    @Test("a missing named topic cannot fall back to unrelated travel or site facts")
    func missingTopicHasOnlyAbsenceEvidence() {
        let visits = [Visit(time: .now, title: "Hotel booking confirmation", url: "https://stay.example/booking/confirmation")]
        let missing = JourneyEvidence.make(visits: visits, question: "Atlantis?", focus: .travel)
        #expect(missing.hasUnmatchedSearch)
        #expect(missing.evidenceLines.count == 1)
        #expect(!missing.evidenceLines.joined().contains("Hotel"))
        #expect(missing.deterministicAnswer.contains("No retained page title or URL matched atlantis"))
        let general = JourneyEvidence.make(visits: visits, question: "Which travel-related pages appear, and when?", focus: .travel)
        #expect(!general.hasUnmatchedSearch)
        let planning = JourneyEvidence.make(visits: visits, question: "Suggest useful evidence trails to revisit. Prioritize concrete research, travel-related pages and tracking patterns.", focus: .overview, matchingRequested: false)
        #expect(!planning.hasUnmatchedSearch)
        #expect(planning.evidenceLines.contains { $0.hasPrefix("booking-like pages:") })
        let named = JourneyEvidence.make(visits: visits, question: "stay.example?", focus: .travel)
        #expect(!named.hasUnmatchedSearch && named.matches.count == 1)
    }

    @Test("question wording is not a missing topic that discards the evidence")
    func questionWordingIsNotAMissingTopic() {
        let visits = [
            Visit(time: .now, title: "Kettle listing", url: "https://shop.example/p/1"),
            Visit(time: .now, title: "Leaving Airbnb", url: "https://airbnb.example/r?u=https%3A%2F%2Fmaps.example%2F%3Fll%3D48.8566%252C2.3522"),
        ]
        let shopping = JourneyEvidence.make(visits: visits, question: "What was I shopping for?", focus: nil)
        #expect(!shopping.hasUnmatchedSearch)
        #expect(shopping.matches.map(\.title) == ["Kettle listing"])
        let exposed = JourneyEvidence.make(visits: visits, question: "Is my location exposed anywhere in my history?", focus: nil)
        #expect(!exposed.hasUnmatchedSearch)
        #expect(exposed.evidenceLines.contains { $0.hasPrefix("location-bearing URLs:") })
        let places = JourneyEvidence.make(visits: visits, question: "Which map links contain a named place, and when?", focus: .places)
        #expect(!places.hasUnmatchedSearch)
        #expect(places.evidenceLines.contains { $0.hasPrefix("location-bearing URLs:") })
        let missing = JourneyEvidence.make(visits: visits, question: "What was I knitting?", focus: nil)
        #expect(missing.hasUnmatchedSearch, "a real topic with no matching page still gets only absence evidence")
    }

    @Test("travel example dates cannot be promoted to the full signal range")
    func travelExampleDatesAreNotTheFullRange() throws {
        let first = try #require(ISO8601DateFormatter().date(from: "2026-02-19T12:00:00Z"))
        let last = try #require(ISO8601DateFormatter().date(from: "2026-10-11T12:00:00Z"))
        let visits = [
            Visit(time: first, title: "Flight checkout", url: "https://air.example/checkout"),
            Visit(time: last, title: "Hotel confirmation", url: "https://stay.example/booking/confirmation")
        ]
        let evidence = JourneyEvidence.make(visits: visits, question: "travel pages", focus: .travel)
        #expect(evidence.travelSpan == "2026-02-19 through 2026-10-11")
        let packet = ["booking-like pages: 13 signals; full retained signal dates: 2026-02-19 through 2026-10-11; examples Oct 11, 2026 and Jun 13, 2026"]
        #expect(!HistoryJourneyValidation.allowsNarrative("13 travel-related page signals appear from Oct 11, 2026 to Jun 13, 2026.", evidenceLines: packet))
        #expect(HistoryJourneyValidation.allowsNarrative("13 travel-related page signals were retained.", evidenceLines: packet))
        #expect(evidence.deterministicAnswer.contains(evidence.travelSpan))
        #expect(HistoryJourneyValidation.followUpFocus(for: "Travel pages?", previous: .research) == nil)
        #expect(JourneyEvidence.inferredFocus(for: "Travel pages?", visits: []) == .travel)
    }

    @Test("travel packets exclude unrelated confirmations and raw booking paths")
    func travelEvidenceMatchesExploreScope() {
        let visits = [
            Visit(time: .now, title: "Authorize application", url: "https://code.example/login/device/confirmation/private-code"),
            Visit(time: .now, title: "Hotel booking confirmation", url: "https://stay.example/booking/confirmation/private-reservation")
        ]
        let evidence = JourneyEvidence.make(visits: visits, question: "travel pages", focus: .travel)
        let packet = evidence.evidenceLines.joined(separator: "\n")
        #expect(packet.contains("Hotel booking confirmation"))
        #expect(!packet.contains("Authorize application"))
        #expect(!packet.contains("private-code"))
        #expect(!packet.contains("private-reservation"))
        #expect(evidence.travelBookings.count == 1)
        #expect(!evidence.deterministicAnswer.contains("Authorize application"))
        #expect(!packet.contains("location-bearing URLs:"))
    }

    @Test("the travel tool cannot return an unrelated app authorization page")
    func travelToolEnforcesTravelOnly() async throws {
        let tool = JourneyTravelBookingsTool(visits: [
            Visit(time: .now, title: "Authorize application", url: "https://code.example/login/device/confirmation"),
            Visit(time: .now, title: "Hotel booking confirmation", url: "https://stay.example/booking/confirmation")
        ])
        let output = try await tool.call(arguments: .init())
        #expect(output.contains("Hotel booking confirmation"))
        #expect(!output.contains("Authorize application"))
        #expect(output.contains("completion is not verified"))
    }

    @Test("a broad overview does not promote pages matching generic instruction words")
    func overviewDoesNotSelectIncidentalTitles() {
        let visits = [Visit(time: .now, title: "Leading checkout platform", url: "https://fixture.example")]
        let evidence = JourneyEvidence.make(visits: visits, question: "Give an overview of all retained history and leading recorded sites", focus: .overview)
        #expect(evidence.matches.isEmpty)
        #expect(evidence.visitCount == 1)
        let dated = JourneyEvidence.make(visits: visits, question: "Give an overview of the last 30 days with leading visits", focus: .overview)
        #expect(dated.matches.isEmpty)
        #expect(!evidence.evidenceLines.contains { $0.hasPrefix("matching visits:") })
    }

    @Test("short new topics switch profiles while genuine follow-ups retain focus")
    func followUpsDoNotCaptureNewTopics() {
        #expect(HistoryJourneyValidation.followUpFocus(for: "And when?", previous: .travel) == .travel)
        #expect(HistoryJourneyValidation.followUpFocus(for: "Research threads?", previous: .travel) == nil)
        #expect(HistoryJourneyValidation.followUpFocus(for: "And privacy?", previous: .travel) == nil)
        #expect(HistoryJourneyValidation.followUpFocus(for: "Tell me more", previous: .research) == .research)
        #expect(HistoryJourneyValidation.followUpFocus(for: "Narrow this to the last 30 days", previous: .research) == .research)
        #expect(HistoryJourneyValidation.followUpFocus(for: "Give an overview of the last 30 days", previous: .travel) == nil)
        #expect(HistoryJourneyValidation.followUpFocus(for: "And when?", previous: nil) == nil)
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

private func nonCooperativeWork() -> Int {
    Thread.sleep(forTimeInterval: 2)
    return 7
}

private final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    func add() { lock.withLock { count += 1 } }
    func set(_ value: Int) { lock.withLock { count = value } }
    var value: Int { lock.withLock { count } }
}
