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
