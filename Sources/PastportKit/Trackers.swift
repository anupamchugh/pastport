import Foundation

/// A tracking/redirect signal found in history — an outbound interstitial, a
/// redirect chokepoint, or a URL carrying tracking parameters.
public struct TrackerHit: Identifiable {
    public let id = UUID()
    public let host: String
    public let kind: Kind
    public let count: Int
    public let example: String

    public enum Kind: String { case interstitial, redirect, trackingParam = "tracking-param" }

    public init(host: String, kind: Kind, count: Int, example: String) {
        self.host = host
        self.kind = kind
        self.count = count
        self.example = example
    }
}

/// Deterministic scan for outbound-click tracking. No model, nothing leaves the Mac —
/// it just makes visible what sites like Airbnb (You're leaving Airbnb → /interstitial)
/// route your clicks through.
public enum Trackers {
    public static func classify(title: String, url: String) -> TrackerHit.Kind? {
        let t = title.lowercased()
        let u = url.lowercased()
        if u.contains("/interstitial")
            || t.hasPrefix("you're leaving") || t.hasPrefix("you’re leaving") || t.hasPrefix("leaving ") {
            return .interstitial
        }
        if t.hasPrefix("redirecting") || u.contains("/redirect") || u.contains("/l.php") || u.contains("/url?") {
            return .redirect
        }
        if u.contains("utm_") || u.contains("fbclid=") || u.contains("gclid=") || u.contains("mc_eid=") {
            return .trackingParam
        }
        return nil
    }

    public static func scan(from visits: [Visit]) -> [TrackerHit] {
        struct Key: Hashable { let host: String; let kind: TrackerHit.Kind }
        var counts: [Key: (count: Int, example: String)] = [:]
        for visit in visits {
            guard let kind = classify(title: visit.title, url: visit.url) else { continue }
            let key = Key(host: visit.host, kind: kind)
            var entry = counts[key] ?? (0, visit.cleanURL)
            entry.count += 1
            counts[key] = entry
        }
        return counts
            .map { TrackerHit(host: $0.key.host, kind: $0.key.kind, count: $0.value.count, example: $0.value.example) }
            .sorted { $0.count > $1.count }
    }
}
