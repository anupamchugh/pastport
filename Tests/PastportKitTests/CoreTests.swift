import Foundation
import Testing
@testable import PastportKit

@Suite("Core helpers")
struct CoreTests {
    @Test("keywordFrom picks the longest content word, ignoring stopwords")
    func keyword() {
        #expect(keywordFrom("what was I reading about actors this week?") == "actors")
        #expect(keywordFrom("my kyoto trip research") == "research")
        #expect(keywordFrom("what did i see") == nil)  // all stop / <=3-char words
    }

    @Test("Visit redacts query strings and derives a bare host")
    func redaction() {
        let v = Visit(time: .now, title: "x", url: "https://www.example.com/watch?token=secret#frag")
        #expect(v.cleanURL == "https://www.example.com/watch")
        #expect(v.host == "example.com")
        #expect(!v.cleanURL.contains("secret"))
    }
}

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

    @Test func labExportContainsOnlyAggregates() throws {
        let visits = [Visit(time: .now, title: "PRIVATE TITLE", url: "https://example.com/secret?token=PRIVATE")]
        let data = try HistoryAgent.labExperiment(visits: visits, scope: "one source, complete")
        let text = String(decoding: data, as: UTF8.self)
        #expect(!text.contains("PRIVATE") && !text.contains("example.com") && !text.contains("secret"))
        let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(json["modelRuntime"] as? String == "onDevice")
        #expect((json["selectedTools"] as? [String])?.isEmpty == true)
    }
}
