import Foundation
import Testing
@testable import PastportKit

@Suite("Ask about a shared page")
struct SharedPageTests {
    @Test("a web address becomes a question about its site only: no path, query, fragment or www")
    func questionUsesOnlyTheHost() {
        let q = SharedPage.question(for: URL(string: "https://www.Example.com/private/path?token=SECRET&x=1#frag")!)
        #expect(q == "When did I last visit example.com?")
    }

    @Test("only http and https addresses with a real host name are accepted")
    func rejectsEverythingElse() {
        for text in ["file:///private/thing", "javascript:alert(1)", "ftp://example.com/x", "mailto:a@example.com",
                     "https://user:pass@example.com/", "http://192.168.0.1/admin", "https://localhost/", "https:///nohost",
                     "https://exa mple.com/", "https://exam_ple.com/"] {
            #expect(SharedPage.question(for: URL(string: text) ?? URL(string: "about:blank")!) == nil, "accepted \(text)")
        }
    }

    @Test("the generated question gets the exact on-device site answer from imported history")
    func questionReachesTheDirectAnswer() throws {
        let visits = [Visit(time: Date(timeIntervalSince1970: 1_760_000_000), title: "A", url: "https://example.com/a"),
                      Visit(time: Date(timeIntervalSince1970: 1_760_100_000), title: "B", url: "https://example.com/b"),
                      Visit(time: .now, title: "C", url: "https://other.example/c")]
        let question = try #require(SharedPage.question(for: URL(string: "https://www.example.com/whatever?x=1")!))
        let answer = try #require(HistoryFacts.answer(question: question, visits: visits))
        #expect(answer.text.contains("most recent visit to example.com") && answer.text.contains("2 times"))
    }
}

@MainActor
@Suite("Shared page and import hand-offs on the model", .timeLimit(.minutes(1)))
struct SharedPageModelTests {
    private struct Unlocked: Authenticating {
        func unlock(reason: String, graceMinutes: Int) async -> UnlockResult { .unlocked }
        func relock() {}
    }
    private struct Denied: Authenticating {
        func unlock(reason: String, graceMinutes: Int) async -> UnlockResult { .cancelled }
        func relock() {}
    }

    private func model(_ auth: any Authenticating) -> TimelineModel {
        TimelineModel(history: nil, importedHistory: ImportedHistorySource(), authenticator: auth, appleIntelligenceReady: { false })
    }

    @Test("a shared page waits on the locked Ask tab, reads nothing, and a lock forgets it")
    func sharedPageWaitsLocked() {
        let model = model(Unlocked())
        model.openAsk(aboutPage: URL(string: "https://www.example.com/a?q=1")!)
        #expect(model.tab == .ask && model.isLocked && !model.historyLoaded)
        #expect(model.pendingQuestion == "When did I last visit example.com?")
        model.lockAndClear()
        #expect(model.pendingQuestion == nil)
    }

    @Test("an address that is not a web page leaves Ask empty rather than asking something odd")
    func notAWebPage() {
        let model = model(Unlocked())
        model.openAsk(aboutPage: URL(string: "file:///private/x")!)
        #expect(model.pendingQuestion == nil && model.tab == .ask)
    }

    private func exportZipData() throws -> Data {
        let dir = FileManager.default.temporaryDirectory.appending(path: "pastport-share-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let base = Int64(Date.now.timeIntervalSince1970 - 86_400 * 3) * 1_000_000
        let rows = (0..<2).map { "{\"url\":\"https://example.com/p\($0)\",\"title\":\"P\($0)\",\"time_usec\":\(base + Int64($0) * 1_000_000)}" }.joined(separator: ",")
        try Data("{\"metadata\":{\"browser_name\":\"Safari\",\"data_type\":\"history\"},\"history\":[\(rows)]}".utf8)
            .write(to: dir.appending(path: "History.json"))
        let zip = Process()
        zip.executableURL = URL(filePath: "/usr/bin/zip"); zip.currentDirectoryURL = dir
        zip.arguments = ["-q", "e.zip", "History.json"]
        try zip.run(); zip.waitUntilExit()
        return try Data(contentsOf: dir.appending(path: "e.zip"))
    }

    @Test("a shared page's question waits through the import, is asked once from the imported history, and is then gone")
    func sharedPageThenImport() async throws {
        let model = model(Unlocked())
        model.openAsk(aboutPage: URL(string: "https://example.com/anything?q=secret")!)
        model.importSafariExport(data: try exportZipData())
        let deadline = ContinuousClock.now + .seconds(8)
        while (model.turns.first?.status ?? .answering) == .answering && ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(model.turns.count == 1 && model.turns.first?.prompt == "When did I last visit example.com?")
        #expect(model.turns.first?.answer.contains("2 times") == true)
        #expect(model.pendingQuestion == nil)
        model.lockAndClear()
        #expect(model.turns.isEmpty && model.pendingQuestion == nil && !model.importedHistoryActive)
    }
}
