import Foundation
import PastportKit

/// One simple question about a fixed, fictional history, with the answer worked out in Swift.
public struct AskEvalQuestion: Sendable {
    public let id: String
    public let question: String
    /// What a correct answer says, in plain words. Printed next to the model's answer.
    public let truth: String
    /// Every group must be matched; inside a group any one alternative is enough. Case-insensitive.
    public let mustContain: [[String]]
    /// Phrases that make an answer wrong even when the facts are also present.
    public let mustNotContain: [String]
}

public struct AskEvalResult: Sendable {
    public let question: AskEvalQuestion
    public let answer: String
    public let correct: Bool
    /// Names and figures in the answer that appear nowhere in the fixture, the question or the truth.
    public let invented: [String]
}

/// A fixed fictional history plus the questions an ordinary person would ask of it. Nothing
/// here reads Safari. Dates are relative to `now`, so "yesterday" is always yesterday.
public struct AskEvalFixture: Sendable {
    public let visits: [Visit]
    public let questions: [AskEvalQuestion]
    public let now: Date

    public init(now: Date = Date(), calendar: Calendar = .current) {
        self.now = now
        let startOfToday = calendar.startOfDay(for: now)
        func day(_ offset: Int, hour: Int = 12) -> Date {
            let d = calendar.date(byAdding: .day, value: offset, to: startOfToday) ?? startOfToday
            return calendar.date(byAdding: .hour, value: hour, to: d) ?? d
        }
        // The most recent June that has started, mid-month, so it never straddles a time zone.
        let parts = calendar.dateComponents([.year, .month], from: now)
        let juneYear = (parts.month ?? 12) >= 6 ? (parts.year ?? 2026) : (parts.year ?? 2026) - 1
        func june(_ d: Int) -> Date { calendar.date(from: DateComponents(year: juneYear, month: 6, day: d, hour: 12)) ?? now }

        var v: [Visit] = []
        func add(_ time: Date, _ host: String, _ title: String, _ path: String) {
            v.append(Visit(time: time, title: title, url: "https://\(host)\(path)"))
        }
        // wiki.example 9 · news.example 6 · shop.example 5 · search.example 4 · recipes.example 3 · three more single-visit hosts
        for offset in [-1, -1, -3, -9, -14, -20, -26, -40, -55] { add(day(offset, hour: 9 + abs(offset) % 5), "wiki.example", "Article \(abs(offset))", "/wiki/a\(abs(offset))") }
        for offset in [-1, -4, -12, -19, -33, -48] { add(day(offset, hour: 14), "news.example", "Headlines \(abs(offset))", "/n/\(abs(offset))") }
        for offset in [-6, -22, -35, -60, -75] { add(day(offset, hour: 16), "shop.example", "Kettle listing \(abs(offset))", "/p/\(abs(offset))") }
        for offset in [0, 0, -17] { add(day(offset, hour: 18 + abs(offset) % 3), "recipes.example", "Soup recipe \(abs(offset))", "/r/\(abs(offset))") }
        add(day(-2, hour: 20), "search.example", "kyoto temples - Search", "/search?q=kyoto+temples")
        add(day(-3, hour: 20), "search.example", "kyoto train pass - Search", "/search?q=kyoto+train+pass")
        add(day(-4, hour: 20), "search.example", "kyoto hotels - Search", "/search?q=kyoto+hotels")
        add(day(-11, hour: 20), "search.example", "rust borrow checker - Search", "/search?q=rust+borrow+checker")
        add(june(12), "stay.example", "Booking confirmed — Seaside Hotel", "/booking/confirmation")
        add(june(14), "flights.example", "Your itinerary", "/itinerary/seaside-trip")
        add(day(-30, hour: 11), "airbnb.example", "Leaving Airbnb",
            "/interstitial?r=https%3A%2F%2Fmaps.example%2F%3Fq%3D18%2BRue%2BDemo%252C%2B5th%2BArrondissement%252C%2BParis%252C%2BFrance%26ll%3D48.8566%252C2.3522")
        visits = v

        func count(_ pred: (Visit) -> Bool) -> Int { v.filter(pred).count }
        let start7 = calendar.date(byAdding: .day, value: -7, to: now) ?? now
        let start30 = calendar.date(byAdding: .day, value: -30, to: now) ?? now
        func hostCounts(since: Date) -> [(String, Int)] {
            Dictionary(grouping: v.filter { $0.time >= since && $0.time <= now }, by: \.host)
                .map { ($0.key, $0.value.count) }.sorted { $0.1 != $1.1 ? $0.1 > $1.1 : $0.0 < $1.0 }
        }
        let yesterday = count { calendar.isDate($0.time, inSameDayAs: day(-1)) }
        let today = count { calendar.isDate($0.time, inSameDayAs: day(0)) }
        let last7 = count { $0.time >= start7 && $0.time <= now }
        let topLast7 = hostCounts(since: start7).first?.0 ?? ""
        let topLast30 = hostCounts(since: start30).first?.0 ?? ""
        let lastNews = v.filter { $0.host == "news.example" }.map(\.time).max() ?? now
        let junePages = 2

        func forms(_ date: Date) -> [String] {
            let iso = date.formatted(.iso8601.year().month().day())
            let f = DateFormatter(); f.calendar = calendar; f.locale = Locale(identifier: "en_US_POSIX")
            func s(_ pattern: String) -> String { f.dateFormat = pattern; return f.string(from: date) }
            return [s("MMM d"), iso, s("MMMM d"), s("d MMM"), s("d MMMM")]
        }

        questions = [
            AskEvalQuestion(id: "top-sites", question: "Which 3 sites did I visit most?",
                            truth: "wiki.example (9), news.example (6), shop.example (5)",
                            mustContain: [["wiki.example"], ["news.example"], ["shop.example"]], mustNotContain: ["recipes.example", "search.example"]),
            AskEvalQuestion(id: "top-site", question: "What is my most visited site?",
                            truth: "wiki.example with 9 visits",
                            mustContain: [["wiki.example"], ["9"]], mustNotContain: ["news.example"]),
            AskEvalQuestion(id: "yesterday", question: "How many pages did I visit yesterday?",
                            truth: "\(yesterday) visits yesterday", mustContain: [[String(yesterday)]], mustNotContain: ["unsupported", "can't tell", "cannot tell"]),
            AskEvalQuestion(id: "today", question: "How many pages did I open today?",
                            truth: "\(today) visits today", mustContain: [[String(today)]], mustNotContain: ["unsupported"]),
            AskEvalQuestion(id: "last-visit", question: "When did I last visit news.example?",
                            truth: "the most recent news.example visit was \(forms(lastNews)[1])", mustContain: [forms(lastNews)], mustNotContain: []),
            AskEvalQuestion(id: "searched-yes", question: "Did I search for kyoto?",
                            truth: "yes, three kyoto searches", mustContain: [["yes", "you did", "searched"], ["kyoto"]], mustNotContain: ["no retained", "did not search", "didn't search"]),
            AskEvalQuestion(id: "searched-no", question: "Did I search for quantum?",
                            truth: "no matching search", mustContain: [["no ", "not ", "n't", "nothing", "none"]], mustNotContain: ["yes,", "you did search"]),
            AskEvalQuestion(id: "bookings-june", question: "How many booking pages did I visit in June?",
                            truth: "\(junePages) booking-like pages in June", mustContain: [[String(junePages), "two"]], mustNotContain: ["you booked a", "trip was completed", "purchase was completed"]),
            AskEvalQuestion(id: "places", question: "Which places appear in my history?",
                            truth: "Paris", mustContain: [["paris"]], mustNotContain: ["tokyo", "london", "delhi", "new york"]),
            AskEvalQuestion(id: "absent-site", question: "Did I visit netflix.example?",
                            truth: "no retained visit", mustContain: [["no ", "not ", "n't", "nothing", "none"]], mustNotContain: ["yes,", "you visited netflix"]),
            AskEvalQuestion(id: "last-7-days", question: "How many pages did I visit in the last 7 days?",
                            truth: "\(last7) visits", mustContain: [[String(last7)]], mustNotContain: ["unsupported"]),
            AskEvalQuestion(id: "total", question: "How many pages are in my history?",
                            truth: "\(v.count) visits", mustContain: [[String(v.count)]], mustNotContain: []),
            AskEvalQuestion(id: "researching", question: "What was I researching?",
                            truth: "kyoto trip planning (temples, train pass, hotels)", mustContain: [["kyoto"]], mustNotContain: ["quantum", "tokyo"]),
            AskEvalQuestion(id: "hotel-booked", question: "Did I book a hotel?",
                            truth: "only that a booking page was visited; completion is not proven", mustContain: [["page", "visit", "evidence"]], mustNotContain: ["you booked a hotel", "you have booked", "is confirmed", "was confirmed", "completed your"]),
            AskEvalQuestion(id: "top-last-week", question: "Which site did I visit most last week?",
                            truth: topLast7, mustContain: [[topLast7]], mustNotContain: ["unsupported"]),
            AskEvalQuestion(id: "top-last-month", question: "Which site did I visit most last month?",
                            truth: topLast30, mustContain: [[topLast30]], mustNotContain: ["unsupported"]),
        ]
    }

    /// Text a grounded answer may draw names and figures from.
    var corpus: String {
        visits.map {
            "\($0.host) \($0.title) \($0.url) " + $0.time.formatted(.iso8601.year().month().day())
                + " " + $0.time.formatted(.dateTime.month(.abbreviated).day().year())
        }.joined(separator: "\n")
            + "\n" + questions.map { $0.question + " " + $0.truth }.joined(separator: "\n")
            // Fixed wording the code-side answers use, so template words are not scored as inventions.
            + "\nCounts are page visits, not time spent. last week (7 days) last month (30 days)"
    }
}

public enum AskEval {
    public static func score(_ question: AskEvalQuestion, answer: String, corpus: String) -> AskEvalResult {
        let text = answer.lowercased()
        let hasAll = question.mustContain.allSatisfy { group in group.contains { text.contains($0.lowercased()) } }
        let clean = !question.mustNotContain.contains { text.contains($0.lowercased()) }
        let invented = Eval.groundedness(answer: answer, evidence: corpus).invented
        return AskEvalResult(question: question, answer: answer, correct: hasAll && clean, invented: invented)
    }

    public static func run(
        fixture: AskEvalFixture,
        answer: (AskEvalFixture, String) async throws -> String
    ) async -> [AskEvalResult] {
        var results: [AskEvalResult] = []
        for q in fixture.questions {
            let text: String
            do { text = try await answer(fixture, q.question) } catch { text = "ERROR: \(error)" }
            results.append(score(q, answer: text, corpus: fixture.corpus))
        }
        return results
    }

    public static func table(_ results: [AskEvalResult]) -> String {
        var out = ""
        for r in results {
            let flat = r.answer.replacingOccurrences(of: "\n", with: " ")
            out += "\(r.correct ? "PASS" : "FAIL")  \(r.question.id)  invented=\(r.invented.count)\n"
            out += "   Q: \(r.question.question)\n   expected: \(r.question.truth)\n   answered: \(flat.prefix(220))\n"
            if !r.invented.isEmpty { out += "   invented: \(r.invented.joined(separator: ", "))\n" }
        }
        let ok = results.filter(\.correct).count
        out += "\ncorrect \(ok)/\(results.count) · invented claims \(results.reduce(0) { $0 + $1.invented.count })\n"
        return out
    }
}
