import Foundation

/// Deterministic browsing stats — no model, computed straight from visits.
public struct CategoryStat: Identifiable {
    public let id = UUID()
    public let name: String
    public let visits: Int
    public init(name: String, visits: Int) { self.name = name; self.visits = visits }
}

public struct HourStat: Identifiable {
    public let hour: Int   // 0–23
    public let visits: Int
    public var id: Int { hour }
    public init(hour: Int, visits: Int) { self.hour = hour; self.visits = visits }
}

public struct HostStat: Identifiable {
    public let id = UUID()
    public let host: String
    public let visits: Int
    public init(host: String, visits: Int) { self.host = host; self.visits = visits }
}

public struct HistoryStats {
    public let total: Int
    public let categories: [CategoryStat]   // visits per vertical (+ "Other"), most first
    public let hours: [HourStat]            // 24 buckets, 0…23
    public let topHosts: [HostStat]         // top sites by visit count

    public init(total: Int, categories: [CategoryStat], hours: [HourStat], topHosts: [HostStat]) {
        self.total = total
        self.categories = categories
        self.hours = hours
        self.topHosts = topHosts
    }
}

public enum Stats {
    public static func compute(
        from visits: [Visit],
        verticals: [Vertical] = Verticals.load(),
        topHostLimit: Int = 8
    ) -> HistoryStats {
        var categoryCounts: [String: Int] = [:]
        var hostCounts: [String: Int] = [:]
        var hourCounts = Array(repeating: 0, count: 24)
        let calendar = Calendar.current

        for visit in visits {
            let category = verticals.first { Verticals.hostMatches(visit.host, domains: $0.domains) }?.name ?? "Other"
            categoryCounts[category, default: 0] += 1
            hostCounts[visit.host, default: 0] += 1
            hourCounts[calendar.component(.hour, from: visit.time)] += 1
        }

        let categories = categoryCounts
            .map { CategoryStat(name: $0.key, visits: $0.value) }
            .sorted { $0.visits > $1.visits }
        let hours = (0..<24).map { HourStat(hour: $0, visits: hourCounts[$0]) }
        let topHosts = hostCounts
            .map { HostStat(host: $0.key, visits: $0.value) }
            .sorted { $0.visits > $1.visits }
            .prefix(topHostLimit)
            .map { $0 }

        return HistoryStats(total: visits.count, categories: categories, hours: hours, topHosts: Array(topHosts))
    }
}
