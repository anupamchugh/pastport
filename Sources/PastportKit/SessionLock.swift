import Foundation

/// A short-lived unlock grace window, like `sudo`'s timestamp. After one successful
/// Touch ID, repeated commands within `graceMinutes` skip the prompt.
///
/// Security tradeoff: this persists an "unlocked-until" marker on disk, so it is a
/// slightly weaker gate than authenticating every time. It is mitigated by: a short
/// default window, `0600` permissions, an owner/permission tamper check, and storing
/// only a timestamp (no bypass token). Use `--relock` (grace 0) for the strict path.
public enum SessionLock {
    private static var stampURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appending(path: "Library/Application Support")
        return base.appending(path: "Pastport/unlock.stamp")
    }

    /// Returns true if a valid, untampered, in-window unlock stamp exists.
    private static func withinGrace(_ minutes: Int) -> Bool {
        guard minutes > 0 else { return false }
        let url = stampURL
        let fm = FileManager.default
        guard let attrs = try? fm.attributesOfItem(atPath: url.path) else { return false }

        // Tamper check (fail closed): must be owned by us and not group/other-writable.
        guard let owner = attrs[.ownerAccountID] as? NSNumber, owner.uint32Value == getuid() else { return false }
        guard let perms = (attrs[.posixPermissions] as? NSNumber)?.int16Value, (perms & 0o077) == 0 else { return false }

        guard let text = try? String(contentsOf: url, encoding: .utf8),
              let seconds = Double(text.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            return false
        }
        let last = Date(timeIntervalSince1970: seconds)
        return Date().timeIntervalSince(last) < Double(minutes) * 60
    }

    private static func stampNow() {
        let url = stampURL
        let fm = FileManager.default
        try? fm.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try? String(Date().timeIntervalSince1970).write(to: url, atomically: true, encoding: .utf8)
        try? fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    /// Forget any grace window; the next unlock will prompt.
    public static func relock() {
        try? FileManager.default.removeItem(at: stampURL)
    }

    /// Ensure the session is unlocked, reusing a recent unlock when allowed.
    /// Returns: 0 unlocked · 1 failed/cancelled · 2 no auth available.
    public static func ensureUnlocked(reason: String, graceMinutes: Int) -> Int32 {
        if withinGrace(graceMinutes) { return 0 }
        let code = biometricUnlock(reason: reason)
        if code == 0 { stampNow() }
        return code
    }
}
