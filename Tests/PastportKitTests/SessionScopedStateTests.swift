import Foundation
import Testing
@testable import PastportKit

private struct Unlocked: Authenticating {
    func unlock(reason: String, graceMinutes: Int) async -> UnlockResult { .unlocked }
    func relock() {}
}

@MainActor
private final class Scratch: SessionScoped {
    var clears = 0
    func lockAndClear() { clears += 1 }
}

@MainActor
@Suite("Session-scoped state registered by an app layer")
struct SessionScopedStateTests {
    private func model() -> TimelineModel {
        TimelineModel(history: nil, authenticator: Unlocked(), appleIntelligenceReady: { false })
    }

    @Test("asking twice for the same kind returns the same instance, made once")
    func oneInstancePerKind() {
        let model = model()
        var made = 0
        let first = model.sessionState(Scratch.self) { made += 1; return Scratch() }
        let second = model.sessionState(Scratch.self) { made += 1; return Scratch() }
        #expect(first === second)
        #expect(made == 1)
    }

    @Test("every lock clears the registered state")
    func lockClearsRegisteredState() {
        let model = model()
        let scratch = model.sessionState(Scratch.self) { Scratch() }
        model.lockAndClear()
        model.lockAndClear()
        #expect(scratch.clears == 2)
    }

    @Test("a model with nothing registered locks as before")
    func lockWithoutRegisteredState() {
        let model = model()
        model.lockAndClear()
        #expect(model.isLocked)
    }
}
