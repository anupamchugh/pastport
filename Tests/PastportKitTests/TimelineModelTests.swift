// Uses Debug-only sample data (DemoData, demoMode).
#if DEBUG
import Foundation
import Observation
import Testing
@testable import PastportKit

private struct AlwaysUnlocked: Authenticating {
    func unlock(reason: String, graceMinutes: Int) async -> UnlockResult { .unlocked }
    func relock() {}
}

private struct NoPhotos: PhotoLibraryReading {
    func records(since: Date, limit: Int) async throws -> [PhotoRecord] { throw PhotoLibraryError.empty }
}

/// Streams the given updates, then either finishes or waits until it is cancelled.
private struct ScriptedAnswerer: TimelineAnswering {
    let updates: [TimelineAnswerProgress]
    var hangs = false

    func answer(_ question: String, evidence: TimelineEvidence) -> AsyncThrowingStream<TimelineAnswerProgress, any Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                for update in updates { continuation.yield(update) }
                if hangs {
                    while !Task.isCancelled { try? await Task.sleep(for: .milliseconds(5)) }
                    continuation.finish(throwing: CancellationError())
                } else {
                    continuation.finish()
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

private final class Flag: @unchecked Sendable {
    private let lock = NSLock()
    private var raised = false
    func set() { lock.lock(); raised = true; lock.unlock() }
    var value: Bool { lock.lock(); defer { lock.unlock() }; return raised }
}

/// Holds callers until `open()`; lets a test pause a source mid-read.
private actor Gate {
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
    func wait() async {
        if isOpen { return }
        await withCheckedContinuation { waiters.append($0) }
    }
    func open() {
        isOpen = true
        waiters.forEach { $0.resume() }
        waiters = []
    }
}

private struct GatedPhotos: PhotoLibraryReading {
    let gate: Gate
    func records(since: Date, limit: Int) async throws -> [PhotoRecord] {
        await gate.wait()
        return [PhotoRecord(time: Date(), isScreenshot: false, labels: [])]
    }
}

@MainActor
private func waitUntil(_ condition: @MainActor () -> Bool) async throws {
    let deadline = ContinuousClock.now + .seconds(5)
    while !condition() {
        guard ContinuousClock.now < deadline else { Issue.record("Timed out"); return }
        try await Task.sleep(for: .milliseconds(5))
    }
}

@MainActor
@Suite("Timeline model", .timeLimit(.minutes(1)))
struct TimelineModelTests {
    @Test func starterQuestionsOnlyOfferWhatTheDataCanAnswer() throws {
        let model = TimelineModel(history: DemoHistorySource(), authenticator: AlwaysUnlocked(),
                                  timelineAnswerer: ScriptedAnswerer(updates: []), appleIntelligenceReady: { false })
        #expect(model.starterQuestions.isEmpty)
        #expect(!model.hasContent)
        model.demoMode = true
        model.start()
        #expect(model.hasContent)
        #expect(model.starterQuestions.count == 4)
        #expect(model.starterQuestions.contains("How many booking pages did I visit?"))
        #expect(model.focusCards.map(\.focus).contains(.travel))
        // Counts agree with their nouns and never show raw inflection markup.
        let headlines = model.focusCards.map(\.headline)
        #expect(headlines.contains("2 booking pages"))
        #expect(headlines.allSatisfy { !$0.contains("^[") && !$0.contains("inflect") })
    }

    @Test func aSensitiveTopicIsNeverNamedOrCountedOnTheHomeCards() {
        let model = TimelineModel(history: DemoHistorySource(), authenticator: AlwaysUnlocked(),
                                  timelineAnswerer: ScriptedAnswerer(updates: []), appleIntelligenceReady: { false })
        let when = Date()
        func thread(_ term: String) -> IntentThread {
            IntentThread(term: term, related: [], queries: ["\(term) near me"], started: when, destinations: [], searchCount: 3)
        }
        model.threads = [thread("clinic"), thread("kyoto")]
        let research = model.focusCards.first { $0.focus == .research }
        #expect(research?.headline == "Kyoto")
        #expect(research?.detail.isEmpty == true)
        model.threads = [thread("clinic")]
        #expect(model.focusCards.contains { $0.focus == .research } == false)
    }

    private func phoneModel(_ answerer: ScriptedAnswerer) -> TimelineModel {
        TimelineModel(history: nil, photos: NoPhotos(), authenticator: AlwaysUnlocked(),
                      timelineAnswerer: answerer, appleIntelligenceReady: { false })
    }

    @Test func lockClearsEvidenceAndAnswersAndCanReloadOnlyFictionalData() async throws {
        let model = TimelineModel(history: DemoHistorySource(), screenshotReader: ScreenshotReader { _ in ["Receipt"] },
                                  authenticator: AlwaysUnlocked(),
                                  timelineAnswerer: ScriptedAnswerer(updates: []),
                                  appleIntelligenceReady: { false })
        model.demoMode = true
        model.start()
        #expect(!model.movements.isEmpty)
        model.readPhotos()
        #expect(model.photoEvents.count == 1)
        #expect(model.photoEvents.first?.photoCount == 1)
        #expect(model.photoEvents.first?.screenshotCount == 1)
        model.input = "Which sites do I visit most?"
        model.ask()
        try await waitUntil { model.turns.first?.status == .answered && !model.busy }
        #expect(model.turns.count == 1)
        #expect(model.turns.first?.answer.contains("guide.example (3)") == true)
        #expect(model.historyLoaded)
        #expect(!model.sites.isEmpty)
        model.selectFocus(.travel)
        #expect(model.historyFocus == .travel)
        model.addScreenshot(data: Data([0x1]), name: "Receipt")
        try await waitUntil { model.screenshots.count == 1 }
        let beforeLock = model.contentID
        model.lockAndClear()
        #expect(model.contentID != beforeLock)
        #expect(model.movements.isEmpty && model.threads.isEmpty && model.travel.isEmpty)
        #expect(model.photoEvents.isEmpty && model.themes.isEmpty && model.screenshots.isEmpty)
        #expect(model.turns.isEmpty && model.input.isEmpty)
        #expect(!model.busy)
        #expect(!model.historyLoaded && model.sites.isEmpty && model.trackerSignals.isEmpty)
        #expect(model.journeyReceipt == nil && model.suggestedQuestions.isEmpty)
        model.start() // Reappearing window must not repopulate cleared evidence.
        #expect(model.movements.isEmpty && model.photoEvents.isEmpty)
        model.loadTrail()
        #expect(!model.movements.isEmpty)
        #expect(model.status == "Demo data · no history read")
    }

    @Test func phoneHasNoHistoryAndOffersTimelineQuestions() {
        let model = phoneModel(ScriptedAnswerer(updates: []))
        model.start()
        #expect(!model.canReadHistory)
        #expect(model.evidenceSourceTitle == "Timeline")
        model.loadTrail()
        #expect(!model.historyLoaded && !model.busy)
        #expect(model.questions(for: .overview).allSatisfy { !$0.lowercased().contains("site") })
    }

    @Test func streamedAnswerShowsToolsUsed() async throws {
        let model = phoneModel(ScriptedAnswerer(updates: [
            TimelineAnswerProgress(text: "Photos show", toolsUsed: ["photo_activity"], source: .model),
            TimelineAnswerProgress(text: "Photos show one burst.", toolsUsed: ["photo_activity", "timeline_counts"], source: .model),
        ]))
        model.input = "What happened?"
        model.ask()
        try await waitUntil { model.turns.first?.status == .answered }
        let turn = try #require(model.turns.first)
        #expect(turn.answer == "Photos show one burst.")
        #expect(turn.toolsUsed == ["photo_activity", "timeline_counts"])
        #expect(turn.note == nil)
        #expect(!model.busy && !model.isAnswering)
    }

    @Test func stopKeepsPartialAnswerAndIgnoresLateUpdates() async throws {
        let model = phoneModel(ScriptedAnswerer(updates: [
            TimelineAnswerProgress(text: "Partial", toolsUsed: ["photo_activity"], source: .model),
        ], hangs: true))
        model.input = "What happened?"
        model.ask()
        try await waitUntil { model.turns.first?.answer == "Partial" }
        #expect(model.isAnswering)
        model.stopAnswer()
        #expect(model.turns.first?.status == .stopped)
        #expect(model.turns.first?.answer == "Partial")
        #expect(!model.busy && !model.isAnswering)
        try await Task.sleep(for: .milliseconds(50))
        #expect(model.turns.first?.status == .stopped)
        #expect(model.turns.first?.answer == "Partial")
    }

    /// The composer shows Stop while `isAnswering`; a view reading it must hear when it ends.
    @Test func finishingAnAnswerNotifiesObserversOfIsAnswering() async throws {
        let model = phoneModel(ScriptedAnswerer(updates: [
            TimelineAnswerProgress(text: "Done.", source: .facts(reason: "Apple Intelligence is still downloading.")),
        ]))
        model.input = "What happened?"
        let changed = Flag()
        model.ask()
        #expect(model.isAnswering)
        withObservationTracking { _ = model.isAnswering } onChange: { changed.set() }
        try await waitUntil { model.turns.first?.status == .answered }
        #expect(!model.isAnswering)
        #expect(changed.value)
    }

    @Test func staleStoppedTaskDoesNotClearBusyForTheNextRead() async throws {
        let gate = Gate()
        let model = TimelineModel(history: nil, photos: GatedPhotos(gate: gate), authenticator: AlwaysUnlocked(),
                                  timelineAnswerer: ScriptedAnswerer(updates: [
                                      TimelineAnswerProgress(text: "Partial", source: .model),
                                  ], hangs: true),
                                  appleIntelligenceReady: { false })
        model.input = "What happened?"
        model.ask()
        try await waitUntil { model.turns.first?.answer == "Partial" }
        model.stopAnswer()
        model.readPhotos()
        #expect(model.busy)
        try await Task.sleep(for: .milliseconds(100))
        #expect(model.busy, "the stopped answer's task must not end the photo read's busy state")
        await gate.open()
        try await waitUntil { !model.busy }
        #expect(model.photoEvents.count == 1)
    }

    @Test func screenshotFinishingAfterALockIsDropped() async throws {
        let gate = Gate()
        let reader = ScreenshotReader { _ in ["Receipt"] }
        let model = TimelineModel(history: nil, photos: NoPhotos(), screenshotReader: reader,
                                  authenticator: AlwaysUnlocked(), timelineAnswerer: ScriptedAnswerer(updates: []),
                                  appleIntelligenceReady: { false })
        let closedStatus = model.screenshotStatus
        model.addScreenshot(name: "Receipt") {
            await gate.wait()
            return Data([0x1])
        }
        model.lockAndClear()
        await gate.open()
        try await Task.sleep(for: .milliseconds(100))
        #expect(model.screenshots.isEmpty)
        #expect(model.screenshotStatus == closedStatus)
    }

    @Test func lockResetsTheScreenshotStatus() async throws {
        let reader = ScreenshotReader { _ in ["Receipt", "guest@example.com"] }
        let model = TimelineModel(history: nil, photos: NoPhotos(), screenshotReader: reader,
                                  authenticator: AlwaysUnlocked(), timelineAnswerer: ScriptedAnswerer(updates: []),
                                  appleIntelligenceReady: { false })
        let closedStatus = model.screenshotStatus
        model.addScreenshot(data: Data([0x1]), name: "Receipt")
        try await waitUntil { model.screenshots.count == 1 }
        #expect(model.screenshotStatus != closedStatus)
        model.lockAndClear()
        #expect(model.screenshotStatus == closedStatus)
    }

    @Test func macAsksTheTimelineWhenOnlyPhotosOrScreenshotsWereRead() async throws {
        let reader = ScreenshotReader { _ in ["Booking reference 42"] }
        let model = TimelineModel(history: DemoHistorySource(), photos: NoPhotos(), screenshotReader: reader,
                                  authenticator: AlwaysUnlocked(),
                                  timelineAnswerer: ScriptedAnswerer(updates: [
                                      TimelineAnswerProgress(text: "One screenshot was added.", toolsUsed: ["added_screenshots"], source: .model),
                                  ]),
                                  appleIntelligenceReady: { false })
        model.addScreenshot(data: Data([0x1]), name: "Booking")
        try await waitUntil { model.screenshots.count == 1 }
        model.input = "What did I add?"
        model.ask()
        try await waitUntil { model.turns.first?.status == .answered }
        #expect(model.turns.first?.answer == "One screenshot was added.")
        #expect(model.turns.first?.toolsUsed == ["added_screenshots"])
        #expect(model.coverage.isEmpty, "no Safari history was read")
    }

    @Test func factsAnswerCarriesTheReason() async throws {
        let model = phoneModel(ScriptedAnswerer(updates: [
            TimelineAnswerProgress(text: "Nothing has been read yet.",
                                   source: .facts(reason: "Apple Intelligence is turned off in Settings.")),
        ]))
        model.input = "What happened?"
        model.ask()
        try await waitUntil { model.turns.first?.status == .answered }
        #expect(model.turns.first?.note == "Apple Intelligence is turned off in Settings.")
    }

    @Test func historyWithoutAnyModelAnswersFromRecordedFacts() async throws {
        let model = TimelineModel(history: DemoHistorySource(), authenticator: AlwaysUnlocked(),
                                  timelineAnswerer: ScriptedAnswerer(updates: []),
                                  appleIntelligenceReady: { false })
        model.start()
        model.input = "Which travel pages appear?"
        model.ask()
        try await waitUntil { model.turns.first?.status == .answered }
        let turn = try #require(model.turns.first)
        #expect(!turn.answer.isEmpty)
        #expect(turn.note == "Apple Intelligence is unavailable, so these are the recorded facts.")
    }

    @Test func addedScreenshotKeepsOnlyScrubbedTextAndLockRemovesIt() async throws {
        let reader = ScreenshotReader { _ in ["Receipt", "Mail guest@example.com"] }
        let withReader = TimelineModel(history: nil, photos: NoPhotos(), screenshotReader: reader,
                                       authenticator: AlwaysUnlocked(), timelineAnswerer: ScriptedAnswerer(updates: []),
                                       appleIntelligenceReady: { false })
        withReader.addScreenshot(data: Data([0x1]), name: "Receipt")
        try await waitUntil { withReader.screenshots.count == 1 }
        let shot = try #require(withReader.screenshots.first)
        #expect(shot.evidence.scrubbedLines.joined().contains("[EMAIL]"))
        #expect(!shot.evidence.scrubbedLines.joined().contains("guest@example.com"))
        #expect(withReader.timelineEvidence.screenshots.count == 1)
        withReader.lockAndClear()
        #expect(withReader.screenshots.isEmpty)
    }

    @Test func changingWindowLocksAndClears() {
        let model = TimelineModel(history: DemoHistorySource(), authenticator: AlwaysUnlocked(),
                                  timelineAnswerer: ScriptedAnswerer(updates: []),
                                  appleIntelligenceReady: { false })
        model.demoMode = true
        model.start()
        #expect(model.historyLoaded)
        model.days = 30
        #expect(!model.historyLoaded && model.movements.isEmpty)
        #expect(model.status.hasPrefix("Window changed"))
    }
}
#endif

@Suite("Home search and card order")
@MainActor
struct HomeSearchTests {
    private func demoModel() -> TimelineModel {
        let model = TimelineModel(history: DemoHistorySource(), authenticator: AlwaysUnlocked(),
                                  timelineAnswerer: ScriptedAnswerer(updates: []), appleIntelligenceReady: { false })
        model.demoMode = true
        model.start()
        return model
    }

    @Test func searchFindsPagesByEveryWordNewestFirst() {
        let model = demoModel()
        let found = model.search("food guide")
        #expect(found.count == 2)
        #expect(found.first?.time ?? .distantPast >= found.last?.time ?? .distantFuture)
        #expect(model.search("food zzzz").isEmpty)
        #expect(model.search("   ").isEmpty)
    }

    @Test func generalJobsComeBeforeTripsOnTheHomeScreen() {
        let order = demoModel().focusCards.map(\.focus)
        #expect(order.first == .research)
        #expect(order.contains(.privacy))
        #expect(order.last == .travel)
    }
}
