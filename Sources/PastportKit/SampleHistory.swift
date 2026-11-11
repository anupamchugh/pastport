import Foundation

/// Fictional pages for the visible "Try with sample history" button. Every address is on a reserved `.example`
/// host, so nothing here is, or can be mistaken for, a person's browsing. Dated relative to today so "yesterday"
/// and "last week" questions have something to find.
public enum SampleHistory {
    public static var visits: [Visit] {
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
    }

    public static let readingList = [
        ReadingListItem(title: "Slow trains across Europe", url: "https://guide.example/slow-trains"),
        ReadingListItem(title: "How a lens is made", url: "https://news.example/lens"),
        ReadingListItem(title: "A week in Lisbon", url: "https://guide.example/lisbon"),
    ]

    static var export: SafariExportResult {
        let visits = visits
        return SafariExportResult(visits: visits, profiles: 1, rowsRead: visits.count, isPartial: false, readingList: readingList)
    }
}

extension TimelineModel {
    /// The visible "Try with sample history" button: loads the fictional pages above as if they were an export,
    /// so a reviewer or a first-time user can see the timeline, Reading List, Ask, Skeptic and Historian.
    /// It reads no file and nothing from Safari, needs no Face ID because nothing personal is loaded, and every
    /// lock drops it like any import.
    public func trySampleHistory() {
        guard let importedHistory, !busy else { return }
        let export = SampleHistory.export
        importedHistory.load(export)
        importedHistoryActive = true; sampleActive = true
        unlocked = true; isLocked = false
        importStatus = "Sample history: fictional pages. Nothing was read from Safari or this device."
        loadTrail()
    }
}
