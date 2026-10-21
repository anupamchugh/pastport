import Foundation

/// Which tabs share the screen. Narrow widths (iPhone, folded Duo) show one tab; wide widths
/// (Duo unfolded, iPad, a large iPhone in landscape) pair Timeline with Ask and Add with Privacy.
public enum PaneLayout {
    /// Below this container width in points, one pane is shown.
    public static let twoPaneMinimumWidth: Double = 700

    public static func panes(for tab: TimelineModel.Tab, width: Double) -> [TimelineModel.Tab] {
        guard width >= twoPaneMinimumWidth else { return [tab] }
        switch tab {
        case .trail, .ask: return [.trail, .ask]
        case .add, .privacy: return [.add, .privacy]
        }
    }
}
