import Foundation
import FoundationModels

/// The Foundation Lab export, and the read-only history tools that `HistoryJourney` hands the
/// on-device model. The tool-calling agent itself lives in `HistoryJourney`.
public enum HistoryAgent {
    /// A portable Foundation Lab experiment. Only aggregate category counts are
    /// exported: no URLs, page titles, searches, coordinates, or model answers.
    public static func labExperiment(visits: [Visit], scope: String) throws -> Data {
        let stats = Stats.compute(from: visits)
        let categories = stats.categories.prefix(8).map { "\($0.name): \($0.visits)" }.joined(separator: ", ")
        let object: [String: Any] = [
            "name": "Pastport retained-history overview",
            "summary": "Local aggregate evidence selected for export from Pastport. Safari access is not granted.",
            "prompt": "Summarize these browsing counts neutrally. Counts are visits, not time spent. Do not infer identity, sensitive traits, intent or completed actions. Scope: \(scope). Categories: \(categories).",
            "instructions": "Use only the provided aggregate evidence. Say when evidence is insufficient. Do not call external tools.",
            "kind": "conversation", "modelRuntime": "onDevice", "reasoningLevel": "none", "selectedTools": []
        ]
        return try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
    }
}

struct SearchHistoryTool: Tool {
    let name = "search_history"
    let description = "Search the person's Safari history by keyword (matches page title or URL). Returns matching visits with time, title, and host."
    let visits: [Visit]

    @Generable
    struct Arguments {
        @Guide(description: "Keyword to search for — a site, brand, or topic, e.g. 'flights', 'maps', 'news'")
        var keyword: String
    }

    func call(arguments: Arguments) async throws -> String {
        let keyword = arguments.keyword.lowercased()
        let matches = visits.filter {
            $0.title.lowercased().contains(keyword) || $0.url.lowercased().contains(keyword)
        }.prefix(40)
        guard !matches.isEmpty else { return ("No visits match '\(arguments.keyword)'.") }
        let lines = matches.map {
            "\($0.time.formatted(.dateTime.month().day().hour().minute())) | \($0.title) | \($0.host)"
        }.joined(separator: "\n")
        return (lines)
    }
}

struct StatsTool: Tool {
    let name = "get_stats"
    let description = "Get the person's browsing breakdown: total visits, category counts, and top sites."
    let visits: [Visit]

    @Generable
    struct Arguments {}

    func call(arguments: Arguments) async throws -> String {
        let stats = Stats.compute(from: visits)
        let categories = stats.categories.prefix(8).map { "\($0.name): \($0.visits)" }.joined(separator: ", ")
        let sites = stats.topHosts.prefix(8).map { "\($0.host) (\($0.visits))" }.joined(separator: ", ")
        return ("Total \(stats.total). Categories: \(categories). Top sites: \(sites).")
    }
}

struct ThreadsTool: Tool {
    let name = "find_threads"
    let description = "Find clusters of recorded searches and destination sites. Search text is evidence of browsing, not proof of beliefs, intentions or completed actions."
    let visits: [Visit]

    @Generable
    struct Arguments {
        @Guide(description: "Optional word to narrow to one topic, e.g. 'travel'. Leave empty for everything.")
        var about: String
    }

    func call(arguments: Arguments) async throws -> String {
        var threads = Threads.scan(from: visits, limit: 20)
        let filter = arguments.about.trimmingCharacters(in: .whitespaces).lowercased()
        if !filter.isEmpty {
            threads = threads.filter {
                ([$0.term] + $0.related + $0.queries).joined(separator: " ")
                    .lowercased().contains(filter)
            }
        }
        guard !threads.isEmpty else { return "No research threads match." }
        return threads.prefix(8).map {
            "\($0.headline): \($0.queries.prefix(3).joined(separator: "; "))"
        }.joined(separator: "\n")
    }
}

struct BookingsTool: Tool {
    let name = "find_bookings"
    let description = "Find visits to checkout, confirmation, itinerary and ticket pages. These are page signals, not proof of payment, a completed booking or a trip taken."
    let visits: [Visit]

    @Generable
    struct Arguments {
        @Guide(description: "Set true to return only travel — flights, stays and the paperwork around them.")
        var travelOnly: Bool
    }

    func call(arguments: Arguments) async throws -> String {
        var found = Bookings.scan(from: visits)
        if arguments.travelOnly { found = found.filter(\.isTravel) }
        guard !found.isEmpty else { return "No booking-related page signals found." }
        return "Recorded page visits only; completion is not verified.\n" + found.prefix(12).map {
            "\($0.headline)\($0.title.isEmpty ? "" : " — \($0.title.prefix(60))")"
        }.joined(separator: "\n")
    }
}

struct LocationTool: Tool {
    let name = "find_location_leaks"
    let description = "Find coordinates embedded in recorded URLs, with the visit timestamp and source host. A map link does not prove physical presence, a trip or the originating device."
    let visits: [Visit]

    @Generable
    struct Arguments {}

    func call(arguments: Arguments) async throws -> String {
        let leaks = Movements.scan(from: visits)
        guard !leaks.isEmpty else { return ("No location leaks found.") }
        return leaks.prefix(15).map { leak in
            let when = leak.time.formatted(.dateTime.month().day().hour().minute())
            let src = leak.fromApp.map { "redirect link from \($0)" } ?? "map link"
            return "\(when) | \(src) | \(String(format: "%.5f", leak.lat)),\(String(format: "%.5f", leak.lng)) | \(leak.mapProvider)"
        }.joined(separator: "\n")
    }
}
