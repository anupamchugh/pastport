import Foundation
import Testing
@testable import PastportKit

private let cal = Calendar.current
private let today = cal.startOfDay(for: Date(timeIntervalSince1970: 1_799_000_000))

private func visit(_ daysAgo: Int, _ title: String, _ url: String, hour: Int = 10) -> Visit {
    let day = cal.date(byAdding: .day, value: -daysAgo, to: today)!
    return Visit(time: cal.date(byAdding: .hour, value: hour, to: day)!, title: title, url: url)
}

/// 30 active days: guide.example every day, news.example every third day.
private func month() -> [Visit] {
    (0..<30).flatMap { d -> [Visit] in
        var v = [visit(d, "Guide \(d)", "https://guide.example/page/\(d)")]
        if d % 3 == 0 { v.append(visit(d, "News \(d)", "https://news.example/story/\(d)", hour: 12)) }
        return v
    }
}

@Suite("Historian chapters")
struct HistorianChapterTests {
    @Test("a period becomes at most five chapters, oldest first, every visit in exactly one")
    func chaptersCoverThePeriod() {
        let visits = month()
        let chapters = HistorianPlanner.chapters(from: visits)
        #expect(chapters.count == 5)
        #expect(chapters.map(\.start) == chapters.map(\.start).sorted())
        let total = chapters.compactMap { $0.facts.first { $0.hasPrefix("visits: ") } }
            .compactMap { Int($0.dropFirst("visits: ".count).split(separator: " ").first ?? "") }.reduce(0, +)
        #expect(total == visits.count)
        for pair in zip(chapters, chapters.dropFirst()) { #expect(pair.0.end < pair.1.start) }
    }

    @Test("a short period gets one chapter per active day at most, and no visits gives none")
    func smallPeriods() {
        #expect(HistorianPlanner.chapters(from: []).isEmpty)
        let two = [visit(1, "A", "https://a.example/x"), visit(0, "B", "https://b.example/y")]
        #expect(HistorianPlanner.chapters(from: two).count == 2)
    }

    @Test("facts hold counts, top sites and research threads, and no query strings")
    func factsAreComputedByCode() {
        let visits = [
            visit(2, "Kyoto trains - Search", "https://search.example/search?q=kyoto+trains&token=SECRET"),
            visit(2, "Kyoto hotels - Search", "https://search.example/search?q=kyoto+hotels"),
            visit(2, "Kyoto rail pass - Search", "https://search.example/search?q=kyoto+rail+pass"),
            visit(2, "Guide", "https://guide.example/kyoto?utm_source=x"),
        ]
        let chapters = HistorianPlanner.chapters(from: visits)
        #expect(chapters.count == 1, "one active day is one chapter")
        let facts = chapters.flatMap(\.facts).joined(separator: "\n")
        #expect(facts.contains("visits: 4 on 1 active day"))
        #expect(facts.contains("top sites: search.example 3, guide.example 1"))
        #expect(!facts.contains("SECRET") && !facts.contains("utm_") && !facts.contains("?"))
        #expect(chapters[0].fallbackNarration == "You opened 4 pages on 1 active day. Most opened: search.example 3, guide.example 1.")
    }

    @Test("pages on topics Pastport hides are left out of every chapter, counts included")
    func sensitiveTopicsAreLeftOut() {
        let visits = [
            visit(1, "Clinic referral form", "https://health.example/clinic/referral"),
            visit(1, "Guide", "https://guide.example/a"),
        ]
        let facts = HistorianPlanner.chapters(from: visits).flatMap(\.facts).joined(separator: "\n")
        #expect(facts.contains("visits: 1 on 1 active day"))
        #expect(!facts.contains("health.example") && !facts.lowercased().contains("clinic"))
    }

    @Test("the plain fallback narration is built from the facts and passes the story checks")
    func fallbackPassesChecks() {
        for chapter in HistorianPlanner.chapters(from: month()) {
            #expect(HistorianValidation.allows(chapter.fallbackNarration, facts: chapter.facts))
        }
    }
}

@Suite("Historian narration checks")
struct HistorianValidationTests {
    private let facts = ["period: 3 Nov to 9 Nov", "visits: 12 on 4 active days", "top sites: guide.example 5"]

    @Test("prose that stays within the facts is allowed")
    func allowsGroundedProse() {
        #expect(HistorianValidation.allows("From 3 Nov to 9 Nov you opened 12 pages over 4 days, most of them on guide.example.", facts: facts))
    }

    @Test("a number outside the facts, a completed-action claim or an intent claim is refused")
    func refusesOverreach() {
        #expect(!HistorianValidation.allows("You opened 40 pages that week.", facts: facts))
        #expect(!HistorianValidation.allows("You booked a trip and you travelled to Kyoto.", facts: facts))
        #expect(!HistorianValidation.allows("You read the guide closely and you were interested in Kyoto.", facts: facts))
    }

    @Test("empty, over-long or multi-paragraph prose is refused")
    func refusesBadShape() {
        #expect(!HistorianValidation.allows("   ", facts: facts))
        #expect(!HistorianValidation.allows(String(repeating: "word ", count: 120), facts: facts))
        #expect(!HistorianValidation.allows("First part.\n\nSecond part.", facts: facts))
    }
}

private final class Calls: @unchecked Sendable {
    private let lock = NSLock(); private var n = 0
    func add() { lock.withLock { n += 1 } }; var value: Int { lock.withLock { n } }
}
private actor Hold {
    private var open = false; private var waiters: [CheckedContinuation<Void, Never>] = []
    func wait() async { if open { return }; await withCheckedContinuation { waiters.append($0) } }
    func release() { open = true; waiters.forEach { $0.resume() }; waiters = [] }
}
private struct Unlocked: Authenticating {
    func unlock(reason: String, graceMinutes: Int) async -> UnlockResult { .unlocked }
    func relock() {}
}
private struct ScriptedHistorian: HistorianNarrating {
    enum Mode { case says([String]), fails, holds(Hold) }
    struct Boom: Error {}
    let mode: Mode
    let calls = Calls()
    func narrate(facts: [String], voice: HistorianVoice) async throws -> String {
        let index = calls.value
        calls.add()
        switch mode {
        case .says(let lines): return lines[min(index, lines.count - 1)]
        case .fails: throw Boom()
        case .holds(let hold): await hold.wait(); return "Quiet days."
        }
    }
}

@MainActor
@Suite("Historian on the model", .timeLimit(.minutes(1)))
struct HistorianModelTests {
    private func loaded(_ narrator: ScriptedHistorian, ready: Bool = true) async throws -> TimelineModel {
        let source = ImportedHistorySource()
        source.load(SafariExportResult(visits: month().sorted { $0.time > $1.time }, profiles: 1, rowsRead: 45, isPartial: false))
        let model = TimelineModel(history: nil, importedHistory: source, authenticator: Unlocked(),
                                  appleIntelligenceReady: { ready }, historian: narrator, days: 90)
        model.importedHistoryActive = true; model.unlocked = true; model.isLocked = false
        model.loadTrail()
        try await waitUntil { model.historyLoaded }
        return model
    }

    private func waitUntil(_ condition: @MainActor () -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(5)
        while !condition() {
            guard ContinuousClock.now < deadline else { Issue.record("Timed out"); return }
            try await Task.sleep(for: .milliseconds(5))
        }
    }

    @Test("without Apple Intelligence every chapter shows the plain facts narration and the model is never called")
    func factsOnly() async throws {
        let narrator = ScriptedHistorian(mode: .says(["x"]))
        let model = try await loaded(narrator, ready: false)
        model.tellStory()
        try await waitUntil { model.historian?.isRunning == false }
        let story = try #require(model.historian)
        #expect(story.chapters.count == 5 && story.chapters.allSatisfy { $0.origin == .facts })
        #expect(narrator.calls.value == 0)
    }

    @Test("a grounded model narration replaces the plain one; an ungrounded one is refused")
    func modelNarrationIsChecked() async throws {
        let narrator = ScriptedHistorian(mode: .says([
            "The week was quiet and steady.",
            "You opened 9999 pages.",
        ]))
        let model = try await loaded(narrator)
        model.tellStory()
        try await waitUntil { model.historian?.isRunning == false }
        let chapters = try #require(model.historian).chapters
        #expect(chapters[0].origin == .model && chapters[0].narration == "The week was quiet and steady.")
        #expect(chapters[1].origin == .facts && !chapters[1].narration.contains("9999"))
    }

    @Test("a failing model leaves the facts narration and the story still finishes")
    func failureFallsBack() async throws {
        let model = try await loaded(ScriptedHistorian(mode: .fails))
        model.tellStory()
        try await waitUntil { model.historian?.isRunning == false }
        #expect(try #require(model.historian).chapters.allSatisfy { $0.origin == .facts })
    }

    @Test("locking while a chapter is being written clears the story and nothing comes back later")
    func lockClearsTheStory() async throws {
        let hold = Hold()
        let narrator = ScriptedHistorian(mode: .holds(hold))
        let model = try await loaded(narrator)
        model.tellStory()
        try await waitUntil { narrator.calls.value == 1 }
        #expect(model.historian?.isRunning == true)
        model.lockAndClear()
        #expect(model.historian == nil)
        await hold.release()
        try await Task.sleep(for: .milliseconds(150))
        #expect(model.historian == nil)
    }

    @Test("asking for the story twice while it runs starts it once")
    func startsOnce() async throws {
        let hold = Hold()
        let narrator = ScriptedHistorian(mode: .holds(hold))
        let model = try await loaded(narrator)
        model.tellStory(); model.tellStory()
        try await waitUntil { narrator.calls.value == 1 }
        try await Task.sleep(for: .milliseconds(50))
        #expect(narrator.calls.value == 1)
        await hold.release()
        try await waitUntil { model.historian?.isRunning == false }
    }
}
