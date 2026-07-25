import Foundation

public enum CLIError: Error, CustomStringConvertible {
    case msg(String)
    public var description: String {
        switch self { case .msg(let m): return m }
    }
}

/// One Safari page visit.
public struct Visit: Identifiable, Sendable {
    public let id = UUID()
    public let time: Date
    public let title: String
    public let url: String

    public init(time: Date, title: String, url: String) {
        self.time = time
        self.title = title
        self.url = url
    }

    /// URL with the query string and fragment removed (privacy + readability).
    public var cleanURL: String {
        if var comps = URLComponents(string: url) {
            comps.query = nil
            comps.fragment = nil
            return comps.string ?? stripAfterQuestion(url)
        }
        return stripAfterQuestion(url)
    }

    /// Bare host, lowercased, `www.` dropped. Falls back to a substring parse.
    public var host: String {
        let h = URLComponents(string: url)?.host
            ?? cleanURL
                .replacingOccurrences(of: "https://", with: "")
                .replacingOccurrences(of: "http://", with: "")
                .split(separator: "/").first.map(String.init) ?? url
        let lower = h.lowercased()
        return lower.hasPrefix("www.") ? String(lower.dropFirst(4)) : lower
    }

    private func stripAfterQuestion(_ s: String) -> String {
        s.split(separator: "?", maxSplits: 1).first.map(String.init) ?? s
    }
}

/// Run a subprocess and return stdout; throws with stderr on non-zero exit.
@discardableResult
func runProcess(_ launchPath: String, _ arguments: [String]) throws -> String {
    let process = Process()
    process.executableURL = URL(filePath: launchPath)
    process.arguments = arguments
    let out = Pipe()
    let err = Pipe()
    process.standardOutput = out
    process.standardError = err
    try process.run()
    let outData = out.fileHandleForReading.readDataToEndOfFile()
    let errData = err.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    if process.terminationStatus != 0 {
        let message = String(data: errData, encoding: .utf8) ?? "exit \(process.terminationStatus)"
        throw CLIError.msg(message.trimmingCharacters(in: .whitespacesAndNewlines))
    }
    return String(data: outData, encoding: .utf8) ?? ""
}

/// Pull a rough search keyword from a natural-language question — the longest
/// content word — so `ask` can pre-filter rows. Returns nil when nothing stands out.
/// Every content word worth searching on, longest first.
///
/// `keywordFrom` returns only the longest word, which is why "what travel did I book and
/// where did I stay" retrieved YouTube videos tagged #travel and nothing about bookings:
/// "book" and "stay" were discarded. Matching any of the words instead of the best one is
/// the difference between finding a trip and finding a hashtag.
public func keywordsFrom(_ question: String, max: Int = 4) -> [String] {
    let stop: Set<String> = [
        "what", "which", "when", "where", "have", "been", "about", "reading",
        "read", "with", "that", "this", "from", "into", "your", "mine", "were",
        "did", "was", "the", "and", "for", "are", "you", "i", "me", "my", "of",
        "on", "in", "to", "a", "is", "it", "do", "how", "much", "many", "any",
        "history", "safari", "links", "sites", "pages", "visited", "think",
    ]
    var seen = Set<String>()
    return question
        .lowercased()
        .components(separatedBy: CharacterSet.alphanumerics.inverted)
        .filter { $0.count > 3 && !stop.contains($0) && seen.insert($0).inserted }
        .sorted { $0.count > $1.count }
        .prefix(max)
        .map { $0 }
}

public func keywordFrom(_ question: String) -> String? {
    let stop: Set<String> = [
        "what", "which", "when", "where", "have", "been", "about", "reading",
        "read", "with", "that", "this", "from", "into", "your", "mine", "were",
        "did", "was", "the", "and", "for", "are", "you", "i", "me", "my", "of",
        "on", "in", "to", "a", "is", "it", "do", "how", "much", "many", "any",
        "history", "safari", "links", "sites", "pages", "visited",
    ]
    return question
        .lowercased()
        .components(separatedBy: CharacterSet.alphanumerics.inverted)
        .filter { $0.count > 3 && !stop.contains($0) }
        .max(by: { $0.count < $1.count })
}

/// Where this tool keeps its own small state. One definition — it was previously retyped
/// in three files, so moving it meant a grep-and-hope.
public var configDirectory: URL {
    let dir = FileManager.default.homeDirectoryForCurrentUser
        .appending(path: ".config/pastport", directoryHint: .isDirectory)
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
}

/// Something worth telling the person about, once. Every detector produces these, which is
/// what lets `watch` be written once instead of per detector.
public protocol Finding {
    /// Stable identity — "have I already mentioned this?". Must not change between runs.
    var key: String { get }
    /// The one line a notification shows. Deterministic: no model, so it can't be wrong.
    var headline: String { get }
    /// The detail line under the headline.
    var notificationBody: String { get }
}

/// "Have I already told you about this?", persisted. One file per detector.
public struct SeenStore {
    let url: URL

    public init(_ filename: String) {
        self.url = configDirectory.appending(path: filename)
    }

    public func load() -> Set<String> {
        guard let data = try? Data(contentsOf: url),
              let keys = try? JSONDecoder().decode([String].self, from: data) else { return [] }
        return Set(keys)
    }

    public func save(_ keys: Set<String>) {
        try? JSONEncoder().encode(Array(keys)).write(to: url)
    }

    /// Findings not seen before. Records them as seen, so a caller can't forget to.
    /// On a first ever run everything is "new" — seeding silently avoids opening with a
    /// burst of notifications for history the person already lived through.
    public func fresh<F: Finding>(from findings: [F]) -> (new: [F], wasSeeded: Bool) {
        var seen = load()
        let seeding = seen.isEmpty
        let new = findings.filter { !seen.contains($0.key) }
        for finding in new { seen.insert(finding.key) }
        save(seen)
        return (seeding ? [] : new, seeding)
    }
}

/// Fire a native macOS notification. No entitlement needed, and nothing detector-specific
/// about it — which is why it doesn't live inside one.
public func notifyUser(title: String, body: String) {
    func esc(_ s: String) -> String { s.replacingOccurrences(of: "\"", with: "\\\"") }
    let process = Process()
    process.executableURL = URL(filePath: "/usr/bin/osascript")
    process.arguments = ["-e", "display notification \"\(esc(body))\" with title \"\(esc(title))\""]
    try? process.run()
    process.waitUntilExit()
}

/// All Safari history databases: the legacy path plus any Safari 17+ per-profile DBs.
func historyDatabases() -> [URL] {
    let fm = FileManager.default
    let home = fm.homeDirectoryForCurrentUser
    var dbs: [URL] = []

    let legacy = home.appending(path: "Library/Safari/History.db")
    if fm.fileExists(atPath: legacy.path) { dbs.append(legacy) }

    let profiles = home.appending(
        path: "Library/Containers/com.apple.Safari/Data/Library/Safari/Profiles"
    )
    if let entries = try? fm.contentsOfDirectory(at: profiles, includingPropertiesForKeys: nil) {
        for entry in entries {
            let db = entry.appending(path: "History.db")
            if fm.fileExists(atPath: db.path) { dbs.append(db) }
        }
    }
    return dbs
}

/// Copy a History.db (+ its -wal/-shm sidecars, so recent visits aren't lost) to a
/// throwaway temp dir, then run a read query against the copy. Never touches the live file.
private func queryCopy(of db: URL, sql: String) throws -> [[String: Any]] {
    let fm = FileManager.default
    let tmp = fm.temporaryDirectory.appending(
        path: "pastport-\(UUID().uuidString)", directoryHint: .isDirectory
    )
    try fm.createDirectory(at: tmp, withIntermediateDirectories: true)
    defer { try? fm.removeItem(at: tmp) }

    let dest = tmp.appending(path: "History.db")
    try fm.copyItem(at: db, to: dest)   // throws "Operation not permitted" without Full Disk Access
    for sidecar in ["-wal", "-shm"] {
        let src = URL(filePath: db.path + sidecar)
        if fm.fileExists(atPath: src.path) {
            try? fm.copyItem(at: src, to: URL(filePath: dest.path + sidecar))
        }
    }

    let output = try runProcess("/usr/bin/sqlite3", ["-json", dest.path, sql])
    let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty, let data = trimmed.data(using: .utf8) else { return [] }
    return (try JSONSerialization.jsonObject(with: data) as? [[String: Any]]) ?? []
}

/// Fetch visits across all databases within a day window, optionally keyword-filtered.
/// `visit_time` is CFAbsoluteTime (seconds since 2001-01-01), i.e. `timeIntervalSinceReferenceDate`.
public func fetchVisits(days: Int, keyword: String?, limit: Int, hosts: [String] = [],
                        anyOf: [String] = []) throws -> [Visit] {
    let dbs = historyDatabases()
    guard !dbs.isEmpty else {
        throw CLIError.msg("No Safari History.db found for this user.")
    }

    let cutoff = Date().addingTimeInterval(-Double(days) * 86_400).timeIntervalSinceReferenceDate
    var clause = "WHERE v.visit_time > \(cutoff)"
    if let kw = keyword, !kw.isEmpty {
        let safe = kw.replacingOccurrences(of: "'", with: "''")
        clause += " AND (i.url LIKE '%\(safe)%' OR v.title LIKE '%\(safe)%')"
    }
    // Match ANY of several words rather than the single best one — a question usually
    // carries more than one useful noun, and dropping the rest is how "book" and "stay"
    // got thrown away in favour of "travel".
    if !anyOf.isEmpty {
        let terms = anyOf.map { term -> String in
            let safe = term.replacingOccurrences(of: "'", with: "''")
            return "i.url LIKE '%\(safe)%' OR v.title LIKE '%\(safe)%'"
        }.joined(separator: " OR ")
        clause += " AND (\(terms))"
    }
    // Vertical-aware: restrict to given hosts (exact or subdomain) at the SQL level,
    // so a vertical's rows aren't truncated by the volume of other browsing.
    if !hosts.isEmpty {
        let hostClause = hosts.map { host -> String in
            let h = host.replacingOccurrences(of: "'", with: "''")
            return "i.url LIKE '%//\(h)%' OR i.url LIKE '%.\(h)%'"
        }.joined(separator: " OR ")
        clause += " AND (\(hostClause))"
    }
    let sql = """
    SELECT v.visit_time AS t, IFNULL(v.title, '') AS title, i.url AS url \
    FROM history_visits v JOIN history_items i ON i.id = v.history_item \
    \(clause) ORDER BY v.visit_time DESC LIMIT \(limit);
    """

    var firstError: Error?
    var visits: [Visit] = []
    for db in dbs {
        do {
            for row in try queryCopy(of: db, sql: sql) {
                let t = (row["t"] as? Double) ?? (row["t"] as? NSNumber)?.doubleValue ?? 0
                visits.append(
                    Visit(
                        time: Date(timeIntervalSinceReferenceDate: t),
                        title: (row["title"] as? String) ?? "",
                        url: (row["url"] as? String) ?? ""
                    )
                )
            }
        } catch {
            firstError = firstError ?? error
        }
    }
    if visits.isEmpty, let firstError { throw firstError }
    // Dedupe identical visits across profile DBs on (time, url), then keep the
    // global most-recent `limit` — the per-DB SQL LIMIT alone doesn't guarantee this.
    var seen = Set<String>()
    let deduped = visits
        .sorted { $0.time > $1.time }
        .filter { seen.insert("\($0.time.timeIntervalSinceReferenceDate)|\($0.url)").inserted }
    return Array(deduped.prefix(limit))
}

/// Order visits by how many of the question's words they match, so a capped prompt carries
/// the most *relevant* rows rather than the most *recent* ones. Ties break toward newer.
///
/// Without this, "what travel did I book" filled its 60 lines with whatever matched most
/// recently — which was YouTube videos tagged #travel, not bookings.
public func rankVisits(_ visits: [Visit], matching terms: [String], limit: Int) -> [Visit] {
    guard !terms.isEmpty else { return Array(visits.prefix(limit)) }
    return visits
        .map { visit -> (score: Int, visit: Visit) in
            let haystack = (visit.title + " " + visit.url).lowercased()
            return (terms.filter { haystack.contains($0) }.count, visit)
        }
        .sorted { $0.score != $1.score ? $0.score > $1.score : $0.visit.time > $1.visit.time }
        .prefix(limit)
        .map(\.visit)
}

/// Build the analysis prompt for `themes` (question == nil) or `ask` (question set).
public func analysisPrompt(visits: [Visit], question: String?, days: Int, maxLines: Int = 60) -> String {
    // Cap the rows so the prompt fits small on-device context windows
    // (Apple Foundation Models is 4096 tokens; 200 rows overflowed it).
    let lines = visits.prefix(maxLines).map { v -> String in
        let stamp = v.time.formatted(.dateTime.year().month().day().hour().minute())
        return "\(stamp) | \(v.title.isEmpty ? "(no title)" : v.title) | \(v.host)"
    }.joined(separator: "\n")

    if let question, !question.isEmpty {
        return """
        You are analyzing the user's own Safari browsing history (they authorized this). \
        Each line is `TIME | TITLE | HOST`. Answer their question using ONLY these entries; \
        if the answer isn't present, say so plainly. Be concise.

        QUESTION: \(question)

        HISTORY (last \(days) day(s)):
        \(lines)
        """
    }
    return """
    You are analyzing the user's own Safari browsing history (they authorized this). \
    Each line is `TIME | TITLE | HOST`. Group the pages into 4–8 themes by TOPIC \
    (not merely by domain). For each theme give: a short name, the visit count, and \
    2–3 representative titles. Then add a short "Patterns" note (late-night bursts, \
    topics rising or fading, rabbit holes). Do not invent entries. Be concise.

    HISTORY (last \(days) day(s)):
    \(lines)
    """
}
