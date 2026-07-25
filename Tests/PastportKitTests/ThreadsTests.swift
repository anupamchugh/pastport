import XCTest
@testable import PastportKit

final class ThreadsTests: XCTestCase {

    private func visit(_ daysAgo: Int, _ title: String, _ url: String) -> Visit {
        Visit(time: Date().addingTimeInterval(-Double(daysAgo) * 86_400), title: title, url: url)
    }

    // MARK: - query extraction

    func testExtractsQueryFromAnySearchEngineTitle() {
        // The convention, not a named engine — anything matching `… - <Word> Search`.
        XCTAssertEqual(Threads.query(fromTitle: "kyoto has separate visa? - Google Search"),
                       "kyoto has separate visa?")
        XCTAssertEqual(Threads.query(fromTitle: "swift actors - Brave Search"), "swift actors")
        XCTAssertEqual(Threads.query(fromTitle: "kerala rain – Ecosia Search"), "kerala rain")
    }

    func testIgnoresNonSearchTitles() {
        XCTAssertNil(Threads.query(fromTitle: "Hacker News"))
        XCTAssertNil(Threads.query(fromTitle: ""))
        // A page that merely mentions search isn't a results page.
        XCTAssertNil(Threads.query(fromTitle: "How to Search Better | Blog"))
    }

    // MARK: - term filtering

    func testTermsDropStopWordsShortWordsAndNumbers() {
        let terms = Threads.terms(in: "best flights to kyoto 2026 for the visa")
        XCTAssertTrue(terms.contains("kyoto"))
        XCTAssertTrue(terms.contains("visa"))
        XCTAssertTrue(terms.contains("flights"))
        XCTAssertFalse(terms.contains("best"), "stop word")
        XCTAssertFalse(terms.contains("the"), "stop word")
        XCTAssertFalse(terms.contains("2026"), "bare number")
        XCTAssertFalse(terms.contains("for"), "under length floor")
    }

    // MARK: - burst detection

    func testFindsConcentratedBurstAndItsDestinations() {
        let visits = [
            visit(10, "kyoto has separate visa? - Google Search", "https://www.google.com/search"),
            visit(10, "kyoto visa on arrival - Google Search", "https://www.google.com/search"),
            visit(10, "kyoto visa cost - Google Search", "https://www.google.com/search"),
            visit(10, "Visa Requirements", "https://tripadvisor.com/visa"),
            visit(10, "Surf Camp", "https://kimasurf.com/rooms"),
        ]
        let threads = Threads.scan(from: visits)
        XCTAssertEqual(threads.count, 1)

        let thread = threads[0]
        XCTAssertEqual(thread.searchCount, 3)
        // `visa` co-occurs in all three queries, so it merges rather than forming its own thread.
        XCTAssertTrue(thread.term == "kyoto" || thread.related.contains("kyoto"))
        XCTAssertTrue(thread.destinations.contains("tripadvisor.com"))
        // The engine that served the searches must never be listed as a destination.
        XCTAssertFalse(thread.destinations.contains("google.com"))
    }

    func testEvergreenTermsAreNotThreads() {
        // Same search count as the burst above, but spread across two months: a habit,
        // not a decision. This is the check that keeps 9,000-hits-a-year terms out.
        let visits = (0..<3).map { i in
            visit(i * 30, "something reddit - Google Search", "https://www.google.com/search")
        }
        XCTAssertTrue(Threads.scan(from: visits).isEmpty)
    }

    func testTooFewSearchesIsNotAThread() {
        let visits = [
            visit(2, "kerala houseboat - Google Search", "https://www.google.com/search"),
            visit(2, "kerala backwaters - Google Search", "https://www.google.com/search"),
        ]
        XCTAssertTrue(Threads.scan(from: visits).isEmpty)
    }

    func testEmptyHistoryYieldsNoThreads() {
        XCTAssertTrue(Threads.scan(from: []).isEmpty)
    }

    // MARK: - output shape

    private func sample() -> IntentThread {
        IntentThread(term: "kyoto", related: ["visa"],
                     queries: ["kyoto visa", "kyoto visa cost"], started: Date(),
                     destinations: ["tripadvisor.com"], searchCount: 3)
    }

    func testPromptStaysSmallAndNamesNothingExtra() {
        let prompt = Threads.narrationPrompt(for: sample())
        XCTAssertTrue(prompt.contains("kyoto visa"))
        XCTAssertTrue(prompt.contains("tripadvisor.com"))
        // One thread per session, so the prompt should be tiny next to a 4096-token window.
        XCTAssertLessThan(prompt.count, 1_200)
    }

    func testSteerReachesThePromptWhenGiven() {
        XCTAssertFalse(Threads.narrationPrompt(for: sample()).contains("be blunt"))
        XCTAssertTrue(
            Threads.narrationPrompt(for: sample(), instruction: "be blunt").contains("be blunt")
        )
    }

    // A burst detector has no idea what it is surfacing — it will put a medical or legal
    // topic in the default view as readily as a holiday. These are the threads that must
    // not render their own topic word on a shared screen.
    func testHealthAndDistressThreadsAreGated() {
        func thread(_ term: String, _ query: String) -> IntentThread {
            IntentThread(term: term, related: [], queries: [query], started: Date(),
                         destinations: [], searchCount: 3)
        }
        XCTAssertTrue(thread("clinic", "clinic referral waiting time").isSensitive)
        XCTAssertTrue(thread("surgery", "surgery recovery timeline").isSensitive)
        XCTAssertTrue(thread("lawyer", "lawyer for a custody dispute").isSensitive)
    }

    func testOrdinaryThreadsAreNotGated() {
        // Over-gating is its own failure — a locked card the person can't act on is noise.
        func thread(_ term: String, _ query: String) -> IntentThread {
            IntentThread(term: term, related: [], queries: [query], started: Date(),
                         destinations: [], searchCount: 3)
        }
        XCTAssertFalse(thread("kyoto", "kyoto has separate visa?").isSensitive)
        XCTAssertFalse(thread("karpathy", "andrej karpathy github").isSensitive)
        XCTAssertFalse(thread("porto", "porto airport nearby hotels").isSensitive)
    }

    func testDigestLineCarriesHeadlineAndQueries() {
        let line = sample().digestLine
        XCTAssertTrue(line.contains("kyoto"))
        XCTAssertTrue(line.contains("kyoto visa cost"))
    }

    // Non-search pages are the overwhelming majority of any history, so a cheap suffix
    // gate runs in front of the regex. These are the exact cases it must not change.
    func testSuffixGateDoesNotChangeResults() {
        let cases: [(String, String?)] = [
            ("kyoto visa - Google Search", "kyoto visa"),
            ("swift actors - Brave Search", "swift actors"),
            ("Hacker News", nil),
            ("How to Search Better | Blog", nil),   // contains "Search", doesn't end with it
            ("Nepal dating - Reddit Search!", nil), // trailing punctuation, not a results page
        ]
        for (title, expected) in cases {
            XCTAssertEqual(Threads.query(fromTitle: title), expected, "for title: \(title)")
        }
    }
}
