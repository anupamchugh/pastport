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

    /// Compact width has four tabs. Regular width has one per pair, since the pair's panes are both on screen.
    public static func tabs(isRegularWidth: Bool) -> [TimelineModel.Tab] {
        isRegularWidth ? [.trail, .add] : TimelineModel.Tab.allCases
    }

    /// The tab to highlight for the selected one.
    public static func tab(for selection: TimelineModel.Tab, isRegularWidth: Bool) -> TimelineModel.Tab {
        panes(for: selection, isRegularWidth: isRegularWidth)[0]
    }

    /// The selection after choosing `tab`: at regular width, choosing the pair already on screen changes nothing.
    public static func selecting(_ tab: TimelineModel.Tab, current: TimelineModel.Tab, isRegularWidth: Bool) -> TimelineModel.Tab {
        isRegularWidth && panes(for: current, isRegularWidth: true).contains(tab) ? current : tab
    }
}
