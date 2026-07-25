import Foundation
import LocalAuthentication

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
    var authenticated = false
    context.evaluatePolicy(policy, localizedReason: reason) { success, _ in
        authenticated = success
        gate.signal()
    }
    gate.wait()
    return authenticated ? 0 : 1
}
