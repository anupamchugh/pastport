import Foundation

/// The Mac's screen-lock signal. iOS uses scene phase instead.
public enum ScreenLock {
    @MainActor public static func onLock(_ action: @escaping @MainActor () -> Void) {
        _ = DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("com.apple.screenIsLocked"), object: nil, queue: .main
        ) { _ in
            Task { @MainActor in action() }
        }
    }
}
