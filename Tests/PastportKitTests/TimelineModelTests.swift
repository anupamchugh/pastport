import Foundation
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
    private func phoneModel(_ answerer: ScriptedAnswerer) -> TimelineModel {
        TimelineModel(history: nil, photos: NoPhotos(), authenticator: AlwaysUnlocked(),
                      timelineAnswerer: answerer, appleIntelligenceReady: { false })
    }

    @Test func lockClearsEvidenceAndAnswersAndCanReloadOnlyFictionalData() {
        let model = TimelineModel(history: DemoHistorySource(), authenticator: AlwaysUnlocked(),
                                  timelineAnswerer: ScriptedAnswerer(updates: []),
                                  appleIntelligenceReady: { false })
        model.demoMode = true
        model.start()
        #expect(!model.movements.isEmpty)
        model.readPhotos()
        #expect(model.photoEvents.count == 1)
        #expect(model.photoEvents.first?.photoCount == 1)
        #expect(model.photoEvents.first?.screenshotCount == 1)
        model.input = "Where did I go?"
        model.ask()
        #expect(model.turns.count == 1 && model.turns.first?.status == .answered)
        #expect(model.historyLoaded)
        #expect(!model.sites.isEmpty)
        model.selectFocus(.travel)
        #expect(model.historyFocus == .travel)
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
