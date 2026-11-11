#if DEBUG
import Foundation

/// Fictional rows for screenshots and manual UI review.
///
/// Debug builds only. Demo mode is opt-in (`--demo` or `PASTPORT_DEMO=1`) and never reads Safari.
public enum DemoData {
    public static var visits: [Visit] { SampleHistory.visits }
}

/// Fictional rows for previews, tests and debug screenshots. Never reads Safari.
public struct DemoHistorySource: HistorySource {
    public init() {}

    public func snapshot(days: Int?) async throws -> HistorySnapshot {
        HistorySnapshot(visits: DemoData.visits, sourceCount: 1,
                        sourceRows: DemoData.visits.count, isComplete: true)
    }
}
#endif
