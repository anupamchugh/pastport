import Foundation

/// A vertical's identity and the domains that route into it — data, not code, so
/// new verticals/domains are added without recompiling.
public struct Vertical: Codable, Identifiable, Sendable {
    public let id: String
    public let name: String
    public let domains: [String]

    public init(id: String, name: String, domains: [String]) {
        self.id = id
        self.name = name
        self.domains = domains
    }
}

public enum Verticals {
    /// Built-in defaults (used when no user config is present).
    public static let defaults: [Vertical] = [
        Vertical(id: "dev", name: "Dev",
                 domains: ["github.com", "stackoverflow.com", "developer.apple.com",
                           "developer.mozilla.org", "npmjs.com", "gitlab.com"]),
        Vertical(id: "ai", name: "AI/Research",
                 domains: ["platform.openai.com", "chatgpt.com", "claude.ai", "console.anthropic.com",
                           "arxiv.org", "huggingface.co", "learn.chatgpt.com"]),
        Vertical(id: "movies", name: "Movies",
                 domains: ["ok.ru", "letterboxd.com", "imdb.com", "justwatch.com",
                           "themoviedb.org", "hotstar.com"]),
        Vertical(id: "video", name: "Video/Music",
                 domains: ["youtube.com", "youtu.be", "spotify.com", "soundcloud.com",
                           "netflix.com", "primevideo.com"]),
        Vertical(id: "social", name: "Social",
                 domains: ["x.com", "twitter.com", "reddit.com", "instagram.com",
                           "linkedin.com", "facebook.com", "threads.net"]),
        Vertical(id: "news", name: "News",
                 domains: ["news.ycombinator.com", "nytimes.com", "bbc.com", "theverge.com",
                           "techcrunch.com", "medium.com", "substack.com"]),
        Vertical(id: "shopping", name: "Shopping",
                 domains: ["amazon.com", "amazon.in", "flipkart.com", "ebay.com", "etsy.com"]),
        Vertical(id: "travel", name: "Travel",
                 domains: ["booking.com", "airbnb.com", "tripadvisor.com", "skyscanner.net", "expedia.com"]),
        Vertical(id: "finance", name: "Finance",
                 domains: ["binance.com", "coinbase.com", "kite.zerodha.com", "tradingview.com"]),
    ]

    /// User-editable override at ~/.config/pastport/verticals.json; falls back to defaults.
    public static func load() -> [Vertical] {
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appending(path: ".config/pastport/verticals.json")
        guard let data = try? Data(contentsOf: url),
              let verticals = try? JSONDecoder().decode([Vertical].self, from: data),
              !verticals.isEmpty else {
            return defaults
        }
        return verticals
    }

    /// Domains for a vertical id, from a (pre-loaded) list to avoid re-reading per call.
    public static func domains(for id: String, in verticals: [Vertical] = load()) -> [String] {
        verticals.first { $0.id == id }?.domains ?? []
    }

    /// True if `host` belongs to any of `domains` (exact or a subdomain).
    public static func hostMatches(_ host: String, domains: [String]) -> Bool {
        domains.contains { host == $0 || host.hasSuffix("." + $0) }
    }
}
