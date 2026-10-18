import Foundation

/// Where retained browsing history comes from. The Mac reads Safari; iOS has no source,
/// because iOS does not let apps read Safari history.
public protocol HistorySource: Sendable {
    /// Nil `days` removes the date filter.
    func snapshot(days: Int?) async throws -> HistorySnapshot
}

public enum UnlockResult: Sendable, Equatable {
    case unlocked
    case cancelled
    /// No biometrics or passcode on this device.
    case unavailable
}

/// The person's approval before a private source opens.
public protocol Authenticating: Sendable {
    func unlock(reason: String, graceMinutes: Int) async -> UnlockResult
    func relock()
}

/// Touch ID / Face ID with passcode fallback, through `SessionLock`.
public struct DeviceAuthenticator: Authenticating {
    public init() {}

    public func unlock(reason: String, graceMinutes: Int) async -> UnlockResult {
        let code = await Task.detached {
            SessionLock.ensureUnlocked(reason: reason, graceMinutes: graceMinutes)
        }.value
        switch code {
        case 0: return .unlocked
        case 2: return .unavailable
        default: return .cancelled
        }
    }

    public func relock() { SessionLock.relock() }
}
