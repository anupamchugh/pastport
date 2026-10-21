import Foundation

/// Which tabs share the screen. Compact width (iPhone, folded Duo) shows one tab; regular width
/// (Duo unfolded, iPad, a large iPhone in landscape) pairs Timeline with Ask and Add with Privacy.
/// The caller passes the horizontal size class, not a measured width, so the system decides.
public enum PaneLayout {
    public static func panes(for tab: TimelineModel.Tab, isRegularWidth: Bool) -> [TimelineModel.Tab] {
        guard isRegularWidth else { return [tab] }
        switch tab {
        case .trail, .ask: return [.trail, .ask]
        case .add, .privacy: return [.add, .privacy]
        }
    }
}
