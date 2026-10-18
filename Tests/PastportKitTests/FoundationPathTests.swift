import XCTest
@testable import PastportKit

/// The on-device tools and the usage accountant, driven from synthetic visits.
/// These tests never open Safari and never start a LanguageModelSession.
final class FoundationPathTests: XCTestCase {

    func testMapAndCheckoutSignalsDoNotClaimCompletedActions() {
        let links = Movements.scan(from: [visit("Google Maps", "https://maps.google.com/?q=48.8584,2.2945")])
        XCTAssertFalse(links.isEmpty)
        XCTAssertFalse(links[0].headline.contains("iPhone"))
        XCTAssertFalse(links[0].headline.contains("You looked"))
        let page = Booking(time: .now, host: "example.com", kind: .checkout, title: "Checkout", url: "https://example.com/checkout")
        XCTAssertTrue(page.headline.contains("checkout page"))
    }

    private func visit(_ title: String, _ url: String, hoursAgo: Int = 1) -> Visit {
        Visit(time: Date().addingTimeInterval(-Double(hoursAgo) * 3600), title: title, url: url)
    }

    func testExposedTokenCountsAreStoredAndMissingCountsAreUnavailable() {
        let exposed = FoundationUsageAccounting.usage(input: 120, output: 40)
        let exposedRun = ModelRun(
            model: "Apple Foundation",
            text: "a grounded answer",
            promptTokens: exposed.input,
            outputTokens: exposed.output,
            totalSeconds: 1.2,
            evalSeconds: 0.4
        )
        XCTAssertEqual(exposed, .available(input: 120, output: 40))
        XCTAssertEqual(exposedRun.promptTokens, 120)
        XCTAssertEqual(exposedRun.outputTokens, 40)

        let missing = FoundationUsageAccounting.usage(input: nil, output: nil)
        let partial = FoundationUsageAccounting.usage(input: 10, output: nil)
        XCTAssertEqual(missing, .unavailable)
        XCTAssertEqual(partial, .unavailable)
        let missingRun = ModelRun(
            model: "Apple Foundation",
            text: "still an answer",
            promptTokens: missing.input,
            outputTokens: missing.output,
            totalSeconds: 0.2,
            evalSeconds: 0.2
        )
        XCTAssertNil(missingRun.promptTokens)
        XCTAssertNil(missingRun.outputTokens)
        XCTAssertNil(missing.input)
        XCTAssertNil(missing.output)
    }

    func testNarrationHasNoPlaceAndAGuardrailSkipsThatThread() {
        let narration = Guided.narration(from: .produced(
            intent: "working out a visa rule",
            exposure: "the searches were recorded"
        ))
        XCTAssertNotNil(narration)
        let labels = Set(Mirror(reflecting: narration!).children.compactMap(\.label))
        XCTAssertEqual(narration?.intent, "working out a visa rule")
        XCTAssertEqual(narration?.exposure, "the searches were recorded")
        XCTAssertEqual(labels, ["intent", "exposure"])
        XCTAssertFalse(labels.contains("place"))
        XCTAssertFalse(labels.contains("city"))
        XCTAssertFalse(labels.contains("country"))
        XCTAssertNil(Guided.narration(from: .guardrailRefusal))
    }

    #if canImport(FoundationModels)
    func testSearchToolUsesOnlyTheVisitsItWasGiven() async throws {
        guard #available(macOS 26, *) else { return }
        let kept = visit("Boarding pass", "https://air.test/eticket")
        let withheld = visit("WITHHELD quartz page", "https://withheld.test/secret")
        let text = try await SearchHistoryTool(visits: [kept]).call(
            arguments: SearchHistoryTool.Arguments(keyword: "boarding")
        )
        XCTAssertTrue(text.contains("Boarding pass"))
        XCTAssertTrue(text.contains("air.test"))
        XCTAssertFalse(text.contains("WITHHELD"))
        XCTAssertFalse(text.contains("withheld.test"))
        XCTAssertFalse(text.contains(withheld.title))
    }

    func testStatsToolReportsOnlyTheGivenVisits() async throws {
        guard #available(macOS 26, *) else { return }
        let kept = visit("A page", "https://included.test/page")
        let text = try await StatsTool(visits: [kept]).call(arguments: StatsTool.Arguments())
        let stats = Stats.compute(from: [kept])
        XCTAssertTrue(text.contains("Total \(stats.total)"))
        XCTAssertTrue(text.contains("included.test"))
        XCTAssertFalse(text.contains("withheld.test"))
    }

    func testThreadsToolReportsOnlyTheGivenSearches() async throws {
        guard #available(macOS 26, *) else { return }
        let kept = [
            visit("kyoto has separate visa? - Google Search", "https://www.google.com/search", hoursAgo: 5),
            visit("kyoto visa on arrival - Google Search", "https://www.google.com/search", hoursAgo: 5),
            visit("kyoto visa cost - Google Search", "https://www.google.com/search", hoursAgo: 5),
            visit("Visa Requirements", "https://tripadvisor.com/visa", hoursAgo: 5),
        ]
        let text = try await ThreadsTool(visits: kept).call(
            arguments: ThreadsTool.Arguments(about: "kyoto")
        )
        let threads = Threads.scan(from: kept, limit: 20)
        XCTAssertFalse(threads.isEmpty)
        XCTAssertTrue(text.contains(threads[0].headline))
        XCTAssertTrue(text.contains("kyoto"))
        XCTAssertFalse(text.contains("zephyr"))
        XCTAssertFalse(text.contains("withheld.test"))
    }

    func testBookingsToolReportsOnlyTheGivenBookings() async throws {
        guard #available(macOS 26, *) else { return }
        let kept = visit("Boarding pass", "https://air.test/eticket")
        let text = try await BookingsTool(visits: [kept]).call(
            arguments: BookingsTool.Arguments(travelOnly: true)
        )
        let found = Bookings.scan(from: [kept])
        XCTAssertFalse(found.isEmpty)
        XCTAssertTrue(text.contains(found[0].headline))
        XCTAssertTrue(text.contains("Boarding pass"))
        XCTAssertFalse(text.contains("WITHHELD stay"))
        XCTAssertFalse(text.contains("withheld-stay.test"))
    }

    func testLocationToolReportsOnlyTheGivenLeaks() async throws {
        guard #available(macOS 26, *) else { return }
        let kept = visit(
            "Listing",
            "https://maps.google.com/maps?q=@12.9716,77.5946"
        )
        let text = try await LocationTool(visits: [kept]).call(arguments: LocationTool.Arguments())
        let leaks = Movements.scan(from: [kept])
        XCTAssertFalse(leaks.isEmpty)
        XCTAssertTrue(text.contains(String(format: "%.5f", leaks[0].lat)))
        XCTAssertTrue(text.contains("12.9716"))
        XCTAssertFalse(text.contains("48.8584"))
        XCTAssertFalse(text.contains("withheld-maps.test"))
    }
    #endif
}
