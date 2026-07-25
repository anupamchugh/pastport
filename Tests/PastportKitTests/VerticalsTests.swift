import Foundation
import Testing
@testable import PastportKit

@Suite("Verticals config")
struct VerticalsTests {
    @Test("Defaults define movies/travel/dev with domains")
    func defaults() {
        let ids = Set(Verticals.defaults.map(\.id))
        #expect(ids.isSuperset(of: ["movies", "travel", "dev", "ai", "social", "news"]))
        #expect(Verticals.domains(for: "movies", in: Verticals.defaults).contains("ok.ru"))
        #expect(Verticals.domains(for: "dev", in: Verticals.defaults).contains("github.com"))
        #expect(Verticals.domains(for: "social", in: Verticals.defaults).contains("reddit.com"))
        #expect(Verticals.domains(for: "nope", in: Verticals.defaults).isEmpty)
    }

    @Test("Host matching handles exact and subdomains, not lookalikes")
    func hostMatch() {
        let d = ["ok.ru", "letterboxd.com"]
        #expect(Verticals.hostMatches("ok.ru", domains: d))
        #expect(Verticals.hostMatches("m.ok.ru", domains: d))
        #expect(!Verticals.hostMatches("notok.ru", domains: d))
        #expect(!Verticals.hostMatches("reddit.com", domains: d))
    }

    @Test("User JSON decodes into verticals")
    func decodesJSON() throws {
        let json = #"[{"id":"music","name":"Music","domains":["last.fm"]}]"#
        let verticals = try JSONDecoder().decode([Vertical].self, from: Data(json.utf8))
        #expect(verticals.first?.id == "music")
        #expect(Verticals.domains(for: "music", in: verticals) == ["last.fm"])
    }
}
