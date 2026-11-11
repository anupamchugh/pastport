import Foundation
import Testing
@testable import PastportKit

@MainActor
@Suite("Import handed over by a Shortcut", .timeLimit(.minutes(1)))
struct ImportFromShortcutTests {
    private struct Unlocked: Authenticating {
        func unlock(reason: String, graceMinutes: Int) async -> UnlockResult { .unlocked }
        func relock() {}
    }
    private struct Denied: Authenticating {
        func unlock(reason: String, graceMinutes: Int) async -> UnlockResult { .cancelled }
        func relock() {}
    }

    private func model(_ auth: any Authenticating) -> TimelineModel {
        TimelineModel(history: nil, importedHistory: ImportedHistorySource(), authenticator: auth, appleIntelligenceReady: { false })
    }

    @Test("an imported zip handed over as bytes asks for authentication first and never reads when it is denied")
    func dataImportNeedsFaceIDFirst() async throws {
        let model = model(Denied())
        model.importSafariExport(data: Data("not a zip".utf8))
        let deadline = ContinuousClock.now + .seconds(5)
        while model.importStatus.isEmpty && ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(5)) }
        #expect(model.importStatus == TimelineModel.unlockFailed, "the bytes were never parsed: a parse would say notAnArchive")
        #expect(!model.importedHistoryActive)
    }

    @Test("bytes that are not a Safari export are refused in plain words and leave nothing imported")
    func dataImportRefusesJunk() async throws {
        let model = model(Unlocked())
        model.importSafariExport(data: Data("not a zip".utf8))
        let deadline = ContinuousClock.now + .seconds(5)
        while model.importStatus.isEmpty && ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(5)) }
        #expect(model.importStatus == SafariExportError.notAnArchive.description)
        #expect(!model.importedHistoryActive && !model.busy)
    }
}
