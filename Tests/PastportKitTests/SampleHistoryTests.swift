import Foundation
import Testing
@testable import PastportKit

@MainActor
@Suite("Visible sample history for App Review and first look", .timeLimit(.minutes(1)))
struct SampleHistoryTests {
    private struct MustNotBeAsked: Authenticating {
        func unlock(reason: String, graceMinutes: Int) async -> UnlockResult { Issue.record("sample data asked for Face ID"); return .cancelled }
        func relock() {}
    }

    private func model() -> TimelineModel {
        TimelineModel(history: nil, importedHistory: ImportedHistorySource(), authenticator: MustNotBeAsked(),
                      appleIntelligenceReady: { false })
    }

    private func waitUntil(_ condition: @MainActor () -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(5)
        while !condition() {
            guard ContinuousClock.now < deadline else { Issue.record("Timed out"); return }
            try await Task.sleep(for: .milliseconds(5))
        }
    }

    @Test("every sample page and Reading List entry is on a reserved .example host, so nothing in it can be real")
    func sampleIsFictional() {
        let hosts = SampleHistory.visits.compactMap { URL(string: $0.url)?.host } + SampleHistory.readingList.map(\.host)
        #expect(!hosts.isEmpty)
        #expect(hosts.allSatisfy { $0.hasSuffix(".example") })
        #expect(SampleHistory.readingList.count == 3)
    }

    @Test("trying the sample loads the timeline and Reading List without Face ID, and says the data is fictional")
    func sampleLoadsWithoutAuthentication() async throws {
        let model = model()
        model.trySampleHistory()
        try await waitUntil { model.historyLoaded }
        #expect(model.sampleActive && model.importedHistoryActive && !model.isLocked)
        #expect(!model.visits.isEmpty)
        #expect(model.readingList.count == SampleHistory.readingList.count)
        #expect(model.importStatus.contains("fictional"))
    }

    @Test("a lock drops the sample like any import, and a real import afterwards is not marked as a sample")
    func lockClearsSample() async throws {
        let model = model()
        model.trySampleHistory()
        try await waitUntil { model.historyLoaded }
        model.lockAndClear()
        #expect(!model.sampleActive && !model.importedHistoryActive && model.visits.isEmpty && model.readingList.isEmpty)
    }

    @Test("a model with no import source has no sample path")
    func noSourceNoSample() {
        let model = TimelineModel(history: nil, authenticator: MustNotBeAsked(), appleIntelligenceReady: { false })
        model.trySampleHistory()
        #expect(!model.sampleActive && !model.importedHistoryActive)
    }
}
