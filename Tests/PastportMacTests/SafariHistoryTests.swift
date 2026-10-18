import Foundation
import Testing
@testable import PastportMac

@Suite("Retained history coverage")
struct HistorySnapshotTests {
    private func database(_ folder: URL, name: String, rows: Int) throws -> URL {
        let url = folder.appending(path: name)
        let inserts = (1...max(1, rows)).prefix(rows).map {
            "INSERT INTO history_visits VALUES(\(Date.now.timeIntervalSinceReferenceDate - Double($0)), 'private-title', 1);"
        }.joined()
        _ = try runProcess("/usr/bin/sqlite3", [url.path, """
        CREATE TABLE history_items(id INTEGER PRIMARY KEY, url TEXT);
        CREATE TABLE history_visits(visit_time REAL, title TEXT, history_item INTEGER);
        INSERT INTO history_items VALUES(1, 'https://example.com/private?secret=hidden');
        \(inserts)
        """])
        return url
    }

    @Test func reportsCapAndEmptySourceTruthfully() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let source = try database(folder, name: "a.db", rows: 3)
        let empty = try database(folder, name: "b.db", rows: 0)
        let capped = try fetchHistorySnapshot(databases: [source, empty], days: nil, limit: 2)
        #expect(capped.sourceCount == 2 && capped.sourceRows == 3)
        #expect(capped.visits.count == 2 && !capped.isComplete)
        let full = try fetchHistorySnapshot(databases: [source, empty], days: nil, limit: 3)
        #expect(full.visits.count == 3 && full.isComplete)
    }

    @Test func neverSilentlyDropsFailedSource() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let source = try database(folder, name: "a.db", rows: 1)
        #expect(throws: (any Error).self) {
            try fetchHistorySnapshot(databases: [source, folder.appending(path: "missing.db")], days: nil, limit: 10)
        }
    }
}
