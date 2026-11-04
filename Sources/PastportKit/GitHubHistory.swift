import Foundation

/// A repository inferred only from a visited github.com URL, not a GitHub API lookup.
public struct GitHubHistoryRepository: Identifiable, Sendable {
    public let name: String
    public let url: URL
    public let lastVisited: Date
    public var id: String { name.lowercased() }
}

public enum GitHubHistory {
    /// Deduplicate repository paths from the already-authorized history snapshot.
    public static func repositories(in visits: [Visit], limit: Int = 20) -> [GitHubHistoryRepository] {
        guard limit > 0 else { return [] }
        let reserved: Set<String> = ["about", "account", "apps", "collections", "contact", "customer-stories", "enterprise", "events", "explore", "features", "issues", "login", "marketplace", "new", "notifications", "orgs", "organizations", "pricing", "pulls", "search", "settings", "sponsors", "topics", "trending", "user-attachments", "users"]
        var seen = Set<String>()
        var result: [GitHubHistoryRepository] = []
        for visit in visits.sorted(by: { $0.time > $1.time }) {
            guard let parts = URLComponents(string: visit.url),
                  ["http", "https"].contains(parts.scheme?.lowercased() ?? ""),
                  parts.host?.lowercased() == "github.com", parts.user == nil, parts.password == nil else { continue }
            let path = parts.path.split(separator: "/", omittingEmptySubsequences: true)
            guard path.count >= 2 else { continue }
            let owner = String(path[0]), repo = String(path[1])
            guard !reserved.contains(owner.lowercased()),
                  owner.range(of: #"^[A-Za-z0-9-]{1,39}$"#, options: .regularExpression) != nil,
                  repo.range(of: #"^[A-Za-z0-9_.-]{1,100}$"#, options: .regularExpression) != nil,
                  repo != ".", repo != ".." else { continue }
            let name = "\(owner)/\(repo)"
            guard seen.insert(name.lowercased()).inserted,
                  let url = URL(string: "https://github.com/\(name)") else { continue }
            result.append(.init(name: name, url: url, lastVisited: visit.time))
            if result.count == limit { break }
        }
        return result
    }
}
