import Testing
@testable import PastportBar

@MainActor
struct PrivacyStateTests {
    @Test func lockClearsEvidenceAndAnswersAndCanReloadOnlyFictionalData() {
        let model = BarModel(demoMode: true)
        model.start()
        #expect(!model.movements.isEmpty)
        model.readPhotos()
        #expect(model.photoEvents.count == 1)
        #expect(model.photoEvents.first?.photoCount == 1)
        #expect(model.photoEvents.first?.screenshotCount == 1)
        model.input = "Where did I go?"
        model.ask()
        #expect(model.log.count == 2)
        let beforeLock = model.contentID
        model.lockAndClear()
        #expect(model.contentID != beforeLock)
        #expect(model.movements.isEmpty && model.threads.isEmpty && model.travel.isEmpty)
        #expect(model.photoEvents.isEmpty && model.themes.isEmpty)
        #expect(model.log.isEmpty && model.input.isEmpty && model.brief.isEmpty)
        #expect(!model.busy)
        model.start() // Reappearing window must not repopulate cleared evidence.
        #expect(model.movements.isEmpty && model.photoEvents.isEmpty)
        model.loadTrail()
        #expect(!model.movements.isEmpty)
        #expect(model.status == "Demo data · no history read")
    }
}
