import XCTest
@testable import PastportKit

final class BookingsTests: XCTestCase {

    private func visit(_ hoursAgo: Int, _ title: String, _ url: String) -> Visit {
        Visit(time: Date().addingTimeInterval(-Double(hoursAgo) * 3600), title: title, url: url)
    }

    // MARK: - shape, not brand

    func testDetectsATransactionOnASiteNobodyHasHeardOf() {
        // The whole point: no domain list. A confirmation looks the same anywhere.
        XCTAssertEqual(
            Bookings.classify(title: "", url: "https://obscure-guesthouse.xyz/booking/confirmation"),
            .confirmation
        )
        XCTAssertEqual(
            Bookings.classify(title: "Your trip to somewhere", url: "https://whatever.test/x"),
            .itinerary
        )
        XCTAssertEqual(
            Bookings.classify(title: "", url: "https://a.test/checkout?step=2"), .checkout
        )
        XCTAssertEqual(
            Bookings.classify(title: "Boarding pass", url: "https://b.test/x"), .ticket
        )
    }

    func testIgnoresMarketingAndBrowsingPages() {
        // "Book a demo" and "books" must not read as transactions — this is why the path
        // signals are specific rather than matching a bare "/book".
        XCTAssertNil(Bookings.classify(title: "Book a demo", url: "https://saas.test/book-a-demo"))
        XCTAssertNil(Bookings.classify(title: "Best books of 2026", url: "https://blog.test/books"))
        XCTAssertNil(Bookings.classify(title: "Hotels in Lisbon", url: "https://search.test/hotels"))
        XCTAssertNil(Bookings.classify(title: "", url: "https://shop.test/border-collie"))
    }

    func testQueryParameterIdentityCountsAsConfirmation() {
        XCTAssertEqual(
            Bookings.classify(title: "", url: "https://x.test/view?booking_id=99"), .confirmation
        )
    }

    // MARK: - scanning

    func testCollapsesAReopenedConfirmationButKeepsASecondBooking() {
        let visits = [
            visit(5, "Booking confirmed", "https://stay.test/booking/confirmation?id=1"),
            visit(4, "Booking confirmed", "https://stay.test/booking/confirmation?id=1"),
            visit(3, "Booking confirmed", "https://stay.test/booking/confirmation?id=1"),
            visit(2, "Boarding pass", "https://air.test/eticket"),
        ]
        let found = Bookings.scan(from: visits)
        XCTAssertEqual(found.count, 2, "one stay + one flight, not four rows")
        XCTAssertEqual(Set(found.map(\.kind)), [.confirmation, .ticket])
    }

    func testNewestFirst() {
        let found = Bookings.scan(from: [
            visit(48, "Booking confirmed", "https://a.test/reservation"),
            visit(1, "Booking confirmed", "https://b.test/reservation"),
        ])
        XCTAssertEqual(found.first?.host, "b.test")
    }

    func testNonTransactionalHistoryYieldsNothing() {
        XCTAssertTrue(Bookings.scan(from: [
            visit(1, "Hacker News", "https://news.ycombinator.com"),
            visit(2, "kyoto visa - Google Search", "https://www.google.com/search"),
        ]).isEmpty)
    }

    func testNameIsDerivedNotLookedUp() {
        XCTAssertEqual(Bookings.name(for: "secure.someairline.co.uk"), "Someairline")
        XCTAssertEqual(Bookings.name(for: "www.example.com"), "Example")
    }
}

final class RetrievalTests: XCTestCase {

    /// The bug this fixes: "what travel did I book and where did I stay" used only the
    /// longest word ("travel") and threw away "book" and "stay".
    func testKeywordsKeepsEveryUsefulWordNotJustTheLongest() {
        let words = keywordsFrom("what travel did I book and where did I stay")
        XCTAssertTrue(words.contains("travel"))
        XCTAssertTrue(words.contains("book"))
        XCTAssertTrue(words.contains("stay"))
        XCTAssertFalse(words.contains("what"), "stop word")
        XCTAssertFalse(words.contains("did"), "stop word")
    }

    func testKeywordsAreCappedAndDeduped() {
        let words = keywordsFrom("travel travel booking booking flight hotel receipt itinerary")
        XCTAssertLessThanOrEqual(words.count, 4)
        XCTAssertEqual(Set(words).count, words.count, "no duplicates")
    }

    /// Ranking is what stops a capped prompt filling up with the most *recent* match
    /// instead of the most *relevant* one.
    func testRankingPrefersRowsMatchingMoreTermsOverNewerRows() {
        let now = Date()
        let hashtagNoise = Visit(time: now, title: "dance reel #travel", url: "https://v.test/1")
        let realBooking = Visit(time: now.addingTimeInterval(-90 * 86_400),
                                title: "Your booking is confirmed — stay",
                                url: "https://stay.test/booking/confirmation")

        let ranked = rankVisits([hashtagNoise, realBooking],
                                matching: ["travel", "book", "stay"], limit: 1)
        XCTAssertEqual(ranked.first?.url, "https://stay.test/booking/confirmation",
                       "a 3-month-old row matching two terms must beat today's single match")
    }

    func testRankingFallsBackToRecencyWithNoTerms() {
        let newer = Visit(time: Date(), title: "a", url: "https://a.test")
        let older = Visit(time: Date().addingTimeInterval(-3600), title: "b", url: "https://b.test")
        XCTAssertEqual(rankVisits([newer, older], matching: [], limit: 1).first?.url,
                       "https://a.test")
    }
}
