import Foundation
import Testing
@testable import PastportKit

@Suite("History question scope")
struct HistoryQuestionScopeTests {
    private let calendar = Calendar(identifier: .gregorian)

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }

    private func visits() -> [Visit] {
        [
            Visit(time: date(2026, 1, 2), title: "recent", url: "https://recent.example"),
            Visit(time: date(2025, 12, 15), title: "month", url: "https://month.example"),
            Visit(time: date(2025, 1, 15), title: "year", url: "https://year.example"),
            Visit(time: date(2024, 6, 1), title: "old", url: "https://old.example"),
            Visit(time: date(2027, 1, 1), title: "future", url: "https://future.example")
        ]
    }

    @Test("date scope follows short follow-ups and explicit all-history resets it")
    func conversationScope() {
        let recent = HistoryQuestionScope.resolve(visits: visits(), question: "last 30 days", nowDate: date(2026, 1, 10))
        let followUp = HistoryQuestionScope.resolve(visits: visits(), question: "And when?", nowDate: date(2026, 1, 10), previousScope: recent)
        #expect(followUp.visits.map(\.title) == ["recent", "month"])
        #expect(followUp.rangeDescription == "last 30 days")
        let empty = HistoryQuestionScope.resolve(visits: visits(), question: "before 2020", previousScope: recent)
        let stillEmpty = HistoryQuestionScope.resolve(visits: visits(), question: "Show more", previousScope: empty)
        #expect(stillEmpty.visits.isEmpty)
        #expect(stillEmpty.rangeDescription == "before 2020")
        let all = HistoryQuestionScope.resolve(visits: visits(), question: "What about all retained history?", previousScope: empty)
        #expect(all.visits.count == visits().count)
        #expect(all.rangeDescription == "retained window")
    }

    @Test("last N days stays inside the supplied snapshot")
    func lastDays() {
        let result = HistoryQuestionScope.resolve(
            visits: visits(), question: "what changed in the last 30 days", nowDate: date(2026, 1, 10)
        )
        #expect(result.visits.map(\.title) == ["recent", "month"])
        #expect(result.rangeDescription == "last 30 days")
        #expect(result.matchedWindow)
        #expect(result.unsupportedReason == nil)
    }

    @Test("named month and year use explicit bounded labels")
    func namedWindows() {
        let month = HistoryQuestionScope.resolve(visits: visits(), question: "last month", nowDate: date(2026, 1, 10))
        #expect(month.rangeDescription == "last month (30 days)")
        #expect(month.visits.map(\.title) == ["recent", "month"])

        let year = HistoryQuestionScope.resolve(visits: visits(), question: "last year", nowDate: date(2026, 1, 10))
        #expect(year.rangeDescription == "last year (365 days)")
        #expect(year.visits.map(\.title) == ["recent", "month", "year"])
    }

    @Test("calendar year and before-year filters do not widen when empty")
    func calendarWindows() {
        let during = HistoryQuestionScope.resolve(visits: visits(), question: "during 2025")
        #expect(during.visits.map(\.title) == ["month", "year"])
        #expect(during.rangeDescription == "during 2025")

        let inYear = HistoryQuestionScope.resolve(visits: visits(), question: "in 2024")
        #expect(inYear.visits.map(\.title) == ["old"])

        let before = HistoryQuestionScope.resolve(visits: visits(), question: "before 2020")
        #expect(before.visits.isEmpty)
        #expect(!before.matchedWindow)
        #expect(before.unsupportedReason == nil)
    }

    @Test("decimal and oversized windows are rejected before arithmetic")
    func boundedParsing() {
        for question in ["last 1.5 days", "last 36501 days", "last 999999999999999999999999 days"] {
            let result = HistoryQuestionScope.resolve(visits: visits(), question: question)
            #expect(result.visits.isEmpty)
            #expect(!result.matchedWindow)
            #expect(result.unsupportedReason != nil)
        }
    }

    @Test("unsupported date words never fall back to all retained visits")
    func unsupportedDoesNotWiden() {
        let result = HistoryQuestionScope.resolve(visits: visits(), question: "what will I visit tomorrow")
        #expect(result.visits.isEmpty)
        #expect(result.unsupportedReason != nil)
    }

    @Test("today, yesterday, last week and a named month are supported windows")
    func everydayWindows() {
        let now = calendar.date(from: DateComponents(year: 2026, month: 10, day: 20, hour: 15))!
        let day = { (offset: Int, hour: Int) in
            self.calendar.date(byAdding: .hour, value: hour, to: self.calendar.date(byAdding: .day, value: offset, to: self.date(2026, 10, 20))!)!
        }
        let source = [
            Visit(time: day(0, 9), title: "today", url: "https://a.example"),
            Visit(time: day(-1, 23), title: "yesterday late", url: "https://b.example"),
            Visit(time: day(-1, 1), title: "yesterday early", url: "https://b.example"),
            Visit(time: day(-5, 12), title: "this week", url: "https://c.example"),
            Visit(time: date(2026, 6, 3), title: "june", url: "https://d.example"),
            Visit(time: date(2026, 6, 30), title: "june end", url: "https://d.example"),
            Visit(time: date(2025, 6, 3), title: "last june", url: "https://e.example"),
        ]
        let resolve = { HistoryQuestionScope.resolve(visits: source, question: $0, nowDate: now) }
        #expect(resolve("how many visits yesterday").visits.count == 2)
        #expect(resolve("what did I open today").visits.count == 1)
        #expect(resolve("top sites last week").visits.count == 4)
        #expect(resolve("how many pages in June").visits.count == 2)
        #expect(resolve("how many pages in June").rangeDescription == "June 2026")
        #expect(resolve("pages in June 2025").visits.count == 1)
        #expect(resolve("pages in December").rangeDescription == "December 2025")
        #expect(resolve("how many visits yesterday").unsupportedReason == nil)
    }

    @Test("questions without a date qualifier preserve the retained snapshot")
    func retainedWindow() {
        let source = visits()
        let result = HistoryQuestionScope.resolve(visits: source, question: "what were my research topics")
        #expect(result.visits.count == source.count)
        #expect(result.rangeDescription == "retained window")
        #expect(result.matchedWindow)
        #expect(result.unsupportedReason == nil)
    }
}
