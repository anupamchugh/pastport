import Foundation
import LocalAuthentication

/// Written once by the system's callback, read after the semaphore releases.
private final class AuthOutcome: @unchecked Sendable { var succeeded = false }

/// Presents the system Touch ID prompt (with login-password / Apple Watch fallback)
/// and blocks until the user decides.
/// Returns: 0 authenticated · 1 failed/cancelled · 2 no auth available.
public func biometricUnlock(reason: String) -> Int32 {
    let context = LAContext()
    context.localizedCancelTitle = "Cancel"

    // Touch ID first, with login-password / Apple Watch fallback. Use
    // `.deviceOwnerAuthenticationWithBiometrics` for biometric-only.
    let policy: LAPolicy = .deviceOwnerAuthentication

    var evalError: NSError?
    guard context.canEvaluatePolicy(policy, error: &evalError) else { return 2 }

    let gate = DispatchSemaphore(value: 0)
    let outcome = AuthOutcome()
    context.evaluatePolicy(policy, localizedReason: reason) { success, _ in
        outcome.succeeded = success
        gate.signal()
    }
    gate.wait()
    return outcome.succeeded ? 0 : 1
}
