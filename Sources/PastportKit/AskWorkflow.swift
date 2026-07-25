import Foundation

/// The deterministic half of Ask. It chooses the smallest evidence slice before a model
/// sees the question; the model is only responsible for phrasing the result.
public enum AskWorkflow {
    public enum Intent: String {
        case location, travel, research, trackers, overview
    }

    public static func intent(for question: String) -> Intent {
        let q = question.lowercased()
        if containsAny(["book", "booking", "flight", "hotel", "stay", "itinerary", "trip", "ticket"], in: q) {
            return .travel
        }
        if containsAny(["where", "went", "go", "left", "located", "place", "airbnb", "map"], in: q) {
            return .location
        }
        if containsAny(["tracked", "tracker", "tracking", "redirect", "utm"], in: q) {
            return .trackers
        }
        if containsAny(["research", "researching", "reading", "read", "working out", "search", "thinking", "topic"], in: q) {
            return .research
        }
        return .overview
    }

    public static func evidence(for intent: Intent, visits: [Visit]) -> String {
        switch intent {
        case .location:
            let leaks = Movements.scan(from: visits)
            guard !leaks.isEmpty else { return "No location leaks found." }
            return leaks.prefix(12).map { leak in
                let place = leak.place ?? "\(Movements.coord(leak.lat)),\(Movements.coord(leak.lng))"
                return "\(leak.headline) | \(place) | \(leak.mapProvider)"
            }.joined(separator: "\n")
        case .travel:
            let bookings = Bookings.scan(from: visits).filter(\.isTravel)
            guard !bookings.isEmpty else { return "No travel bookings found." }
            return bookings.prefix(12).map { "\($0.headline) | \($0.title)" }.joined(separator: "\n")
        case .research:
            let threads = Threads.scan(from: visits, limit: 12)
            guard !threads.isEmpty else { return "No research threads found." }
            return threads.prefix(8).map { "\($0.headline) | \($0.queries.prefix(3).joined(separator: "; "))" }.joined(separator: "\n")
        case .trackers:
            let trackers = Trackers.scan(from: visits)
            guard !trackers.isEmpty else { return "No tracker signals found." }
            return trackers.prefix(12).map { "\($0.host) | \($0.kind.rawValue) | \($0.count)" }.joined(separator: "\n")
        case .overview:
            let stats = Stats.compute(from: visits)
            let categories = stats.categories.prefix(8).map { "\($0.name): \($0.visits)" }.joined(separator: ", ")
            let sites = stats.topHosts.prefix(8).map { "\($0.host): \($0.visits)" }.joined(separator: ", ")
            return "Total visits: \(stats.total). Categories: \(categories). Top sites: \(sites)."
        }
    }

    private static func containsAny(_ words: [String], in text: String) -> Bool {
        let tokens = Set(text.lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted))
        return words.contains { word in
            if word.contains(" ") { return text.localizedCaseInsensitiveContains(word) }
            return tokens.contains(word)
        }
    }
}
