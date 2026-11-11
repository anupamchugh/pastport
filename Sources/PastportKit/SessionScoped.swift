import Foundation

/// State an app layer keeps for one unlocked session and that every lock must drop.
///
/// `TimelineModel` calls `lockAndClear()` on each registered value when it locks. The Connected tools assistant
/// is registered this way, so `PastportKit` itself does not link the packages that assistant needs.
@MainActor
public protocol SessionScoped: AnyObject {
    func lockAndClear()
}

extension TimelineModel {
    /// The one value of `type` for this model, made by `make` on first use. A lock clears it; it is never persisted.
    public func sessionState<State: SessionScoped>(_ type: State.Type, make: () -> State) -> State {
        let key = ObjectIdentifier(type)
        if let existing = sessionScoped[key] as? State { return existing }
        let state = make()
        sessionScoped[key] = state
        return state
    }
}
