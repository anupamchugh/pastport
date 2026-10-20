#if DEBUG
import Foundation

/// Fictional rows for screenshots and manual UI review.
///
/// Debug builds only. Demo mode is opt-in (`--demo` or `PASTPORT_DEMO=1`) and never reads Safari.
public enum DemoData {
    /// Dated relative to today, so "yesterday" and "last week" questions have something to find.
    public static let visits: [Visit] = {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        func at(_ daysAgo: Int, _ hour: Int = 12) -> Date {
            let day = calendar.date(byAdding: .day, value: -daysAgo, to: today) ?? today
            return calendar.date(byAdding: .hour, value: hour, to: day) ?? day
        }
        return [
            Visit(time: at(1, 10), title: "Leaving Airbnb", url: "https://airbnb.example/interstitial?r=https%3A%2F%2Fmaps.example%2F%3Fq%3D18%2BRue%2BDemo%252C%2B5th%2BArrondissement%252C%2BParis%252C%2BFrance%26ll%3D48.8566%252C2.3522"),
            Visit(time: at(2), title: "Your itinerary", url: "https://flights.example/itinerary/demo-trip"),
            Visit(time: at(3), title: "Booking confirmed — Demo Stay", url: "https://stay.example/booking/confirmation"),
            Visit(time: at(4), title: "Demo arrival card", url: "https://forms.example/arrival"),
            Visit(time: at(5, 20), title: "Paris museum hours - Search", url: "https://search.example/search?q=paris+museums"),
            Visit(time: at(6, 20), title: "Train pass options - Search", url: "https://search.example/search?q=train+pass"),
            Visit(time: at(6, 21), title: "Paris restaurants - Search", url: "https://search.example/search?q=paris+restaurants"),
            Visit(time: at(7), title: "Local food guide", url: "https://guide.example/paris"),
            Visit(time: at(1, 9), title: "Local food guide: markets", url: "https://guide.example/paris/markets"),
            Visit(time: at(8), title: "Museum pass", url: "https://guide.example/paris/passes"),
            Visit(time: at(0, 8), title: "Morning headlines", url: "https://news.example/today"),
            Visit(time: at(1, 8), title: "Morning headlines", url: "https://news.example/yesterday"),
            Visit(time: at(9, 8), title: "Weekend reads", url: "https://news.example/weekend"),
        ]
    }()
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
