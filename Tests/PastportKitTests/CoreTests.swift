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

@Suite("Foundation Lab export")
struct LabExportTests {
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
