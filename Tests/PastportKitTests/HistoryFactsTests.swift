import Foundation
import Testing
@testable import PastportKit

@Suite("Direct answers to simple history questions")
struct HistoryFactsTests {
    private let calendar = Calendar(identifier: .gregorian)
    private var now: Date { calendar.date(from: DateComponents(year: 2026, month: 10, day: 20, hour: 15))! }

    private func at(_ offset: Int, _ hour: Int = 12) -> Date {
        let today = calendar.startOfDay(for: now)
        return calendar.date(byAdding: .hour, value: hour, to: calendar.date(byAdding: .day, value: offset, to: today)!)!
    }

    private func visit(_ offset: Int, _ host: String, _ title: String = "Page", path: String = "/") -> Visit {
        Visit(time: at(offset), title: title, url: "https://\(host)\(path)")
    }

    private var visits: [Visit] {
        [visit(-1, "wiki.example"), visit(-1, "wiki.example"), visit(-3, "wiki.example"),
         visit(-1, "news.example"), visit(-9, "news.example"),
         visit(0, "shop.example"),
         visit(-2, "search.example", "kyoto temples - Search", path: "/search?q=kyoto"),
         Visit(time: calendar.date(from: DateComponents(year: 2026, month: 6, day: 12, hour: 12))!,
               title: "Booking confirmed — Seaside Hotel", url: "https://stay.example/booking/confirmation")]
    }

    private func answer(_ q: String) -> String? { HistoryFacts.answer(question: q, visits: visits, now: now)?.text }

    @Test func topSitesRankByCountThenName() {
        let text = answer("Which 2 sites did I visit most?")
        #expect(text?.contains("wiki.example (3), news.example (2)") == true)
        #expect(text?.contains("shop.example") == false)
    }

    @Test func tiesBreakAlphabeticallySoTheAnswerIsStable() {
        let tie = [visit(-1, "b.example"), visit(-1, "a.example")]
        let text = HistoryFacts.answer(question: "top 2 sites", visits: tie, now: now)?.text
        #expect(text?.contains("a.example (1), b.example (1)") == true)
    }

    @Test func singularMostVisitedSiteNamesOne() {
        let text = answer("What is my most visited site?")
        #expect(text?.contains("wiki.example (3)") == true)
        #expect(text?.contains("news.example") == false)
    }

    @Test func yesterdayAndTodayAreCountedNotRefused() {
        #expect(answer("How many pages did I visit yesterday?")?.hasPrefix("3 page visits yesterday") == true)
        #expect(answer("How many pages did I open today?")?.hasPrefix("1 page visit today") == true)
    }

    @Test func lastVisitNamesTheDate() {
        let text = answer("When did I last visit news.example?")
        #expect(text?.contains(at(-9).formatted(.dateTime.month(.abbreviated).day().year())) == false)
        #expect(text?.contains(at(-1).formatted(.dateTime.month(.abbreviated).day().year())) == true)
        #expect(text?.contains("2 times") == true)
    }

    @Test func aSiteNamedByItsFirstWordIsFound() {
        #expect(answer("When did I last visit wiki?")?.contains("wiki.example") == true)
    }

    @Test func anUnknownSiteIsReportedAbsent() {
        #expect(answer("Did I visit netflix.example?")?.hasPrefix("No.") == true)
        #expect(answer("When did I last visit netflix.example?")?.hasPrefix("No visit") == true)
    }

    @Test func searchPagesTitledWithAnEngineNameAreRecognisedToo() {
        let v = [Visit(time: at(-1), title: "kyoto trains - Google Search", url: "https://www.google.example/search?q=kyoto+trains")]
        #expect(HistoryFacts.answer(question: "did I search for trains", visits: v, now: now)?.text.hasPrefix("Yes.") == true)
    }

    @Test func searchesMatchQueriesAndAdmitAbsence() {
        #expect(answer("Did I search for kyoto?")?.hasPrefix("Yes.") == true)
        #expect(answer("Did I search for quantum?")?.hasPrefix("No.") == true)
    }

    @Test func bookingCountUsesTheNamedMonthAndDoesNotClaimAPurchase() {
        let text = answer("How many booking pages did I visit in June?")
        #expect(text?.contains("1 booking page in June 2026") == true)
        #expect(text?.contains("does not prove") == true)
        let didBook = answer("Did I book a hotel?")
        #expect(didBook?.hasPrefix("I can’t tell whether you booked.") == true)
    }

    @Test func totalAndWindowedCountsAgreeWithTheData() {
        #expect(answer("How many pages are in my history?")?.hasPrefix("8 page visits in your history") == true)
        #expect(answer("How many pages did I visit in the last 7 days?")?.hasPrefix("6 page visits in the last 7 days") == true)
    }

    @Test func openEndedQuestionsAreLeftToTheModel() {
        #expect(answer("What was I researching?") == nil)
        #expect(answer("Summarize my recent browsing") == nil)
    }

    @Test func anUnsupportedWindowIsExplainedNotWidened() {
        #expect(answer("How many pages tomorrow?")?.contains("unsupported") == true)
        let text = answer("How many pages in the last 1.5 days?")
        #expect(text?.contains("whole-number window") == true)
    }
}
