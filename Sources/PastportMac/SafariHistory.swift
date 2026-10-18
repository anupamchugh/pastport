import Foundation
import PastportKit

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
            try fm.copyItem(at: src, to: URL(filePath: dest.path + sidecar))
        }
    }

    let output = try runProcess("/usr/bin/sqlite3", ["-json", dest.path, sql])
    let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty, let data = trimmed.data(using: .utf8) else { return [] }
    return (try JSONSerialization.jsonObject(with: data) as? [[String: Any]]) ?? []
}

public func fetchHistorySnapshot(days: Int?, limit: Int = 1_000_000) throws -> HistorySnapshot {
    let fm = FileManager.default
    let home = fm.homeDirectoryForCurrentUser
    func exists(_ url: URL) throws -> Bool {
        do { _ = try fm.attributesOfItem(atPath: url.path); return true }
        catch let error as CocoaError where error.code == .fileReadNoSuchFile || error.code == .fileNoSuchFile {
            return false
        }
    }
    var databases: [URL] = []
    let legacy = home.appending(path: "Library/Safari/History.db")
    if try exists(legacy) { databases.append(legacy) }
    let profiles = home.appending(path: "Library/Containers/com.apple.Safari/Data/Library/Safari/Profiles")
    if try exists(profiles) {
        for folder in try fm.contentsOfDirectory(at: profiles, includingPropertiesForKeys: nil) {
            let db = folder.appending(path: "History.db")
            if try exists(db) { databases.append(db) }
        }
    }
    return try fetchHistorySnapshot(databases: databases, days: days, limit: limit)
}

func fetchHistorySnapshot(databases: [URL], days: Int?, limit: Int) throws -> HistorySnapshot {
    guard !databases.isEmpty else { throw CLIError.msg("No Safari History.db found for this user.") }
    guard limit > 0 else { throw CLIError.msg("History limit must be positive.") }
    let clause = days.map {
        "WHERE v.visit_time > \(Date().addingTimeInterval(-Double(max(1, $0)) * 86400).timeIntervalSinceReferenceDate)"
    } ?? ""
    let sql = """
    SELECT v.visit_time AS t, IFNULL(v.title, '') AS title, i.url AS url,
    COUNT(*) OVER() AS available_count
    FROM history_visits v JOIN history_items i ON i.id = v.history_item
    \(clause) ORDER BY v.visit_time DESC LIMIT \(limit);
    """
    var visits: [Visit] = []
    var sourceRows = 0
    var complete = true
    for db in databases {
        // One failed source fails the read instead of silently declaring full coverage.
        let rows = try queryCopy(of: db, sql: sql)
        let available = (rows.first?["available_count"] as? NSNumber)?.intValue ?? 0
        sourceRows += available
        complete = complete && rows.count == available
        visits += rows.map {
            Visit(time: Date(timeIntervalSinceReferenceDate: ($0["t"] as? NSNumber)?.doubleValue ?? 0),
                  title: $0["title"] as? String ?? "", url: $0["url"] as? String ?? "")
        }
    }
    var seen = Set<String>()
    let unique = visits.sorted { $0.time > $1.time }.filter {
        seen.insert("\($0.time.timeIntervalSinceReferenceDate)|\($0.url)").inserted
    }
    return HistorySnapshot(visits: Array(unique.prefix(limit)), sourceCount: databases.count,
                           sourceRows: sourceRows, isComplete: complete && unique.count <= limit)
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

/// Safari's local history databases, copied and queried read-only. Needs Full Disk Access.
public struct SafariHistorySource: HistorySource {
    public init() {}

    public func snapshot(days: Int?) async throws -> HistorySnapshot {
        try await Task.detached { try fetchHistorySnapshot(days: days) }.value
    }
}
