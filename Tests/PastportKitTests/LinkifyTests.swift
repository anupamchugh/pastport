import Foundation
import Testing
@testable import PastportKit

private func visit(_ title: String, _ url: String, _ minutesAgo: Int = 0) -> Visit {
    Visit(time: Date(timeIntervalSince1970: 1_799_000_000 - Double(minutesAgo) * 60), title: title, url: url)
}

private func linked(_ answer: String, _ spans: [LinkSpan]) -> [String: String] {
    Dictionary(spans.map { (String(answer[$0.range]), $0.url.absoluteString) }, uniquingKeysWith: { first, _ in first })
}

@Suite("Linkify plans links from the person's own evidence")
struct LinkifyTests {
    private let visits = [
        visit("Local food guide", "https://guide.example/paris", 5),
        visit("Search - paris museums", "https://search.example/search?q=paris+museums", 6),
        visit("Morning headlines", "https://news.example/today", 7),
        visit("Morning headlines", "https://news.example/yesterday", 1_500),
        visit("Museum pass", "https://guide.example/paris/passes?utm_source=mail#top", 8),
    ]
    private let reading = [ReadingListItem(title: "Slow trains across Europe", url: "https://guide.example/slow-trains")]

    @Test("a host the person visited becomes a link to that site, and a page title a link to that page")
    func sitesAndPages() {
        let answer = "You read the Local food guide and then spent time on news.example."
        let spans = Linkify.plan(answer: answer, visits: visits, readingList: [])
        #expect(linked(answer, spans) == [
            "Local food guide": "https://guide.example/paris",
            "news.example": "https://news.example/",
        ])
        #expect(spans.map(\.kind) == [.page, .site])
    }

    @Test("a Reading List title links to its saved address")
    func readingListTitle() {
        let answer = "Your Reading List has Slow trains across Europe."
        let spans = Linkify.plan(answer: answer, visits: [], readingList: reading)
        #expect(linked(answer, spans) == ["Slow trains across Europe": "https://guide.example/slow-trains"])
        #expect(spans.first?.kind == .readingList)
    }

    @Test("a name that is not in the evidence is never linked, and no link points to a host outside the evidence")
    func nothingInvented() {
        let answer = "You looked into Lisbon, Marie Curie and example.org last week."
        #expect(Linkify.plan(answer: answer, visits: visits, readingList: reading).isEmpty)
        let all = "Local food guide, news.example, guide.example, Slow trains across Europe"
        let hosts = Set(visits.compactMap { URL(string: $0.url)?.host } + ["guide.example"])
        for span in Linkify.plan(answer: all, visits: visits, readingList: reading) {
            #expect(hosts.contains(span.url.host ?? ""))
        }
    }

    @Test("a title shared by two different pages is ambiguous and is not linked")
    func ambiguousTitle() {
        let answer = "You opened Morning headlines twice."
        #expect(Linkify.plan(answer: answer, visits: visits, readingList: []).isEmpty)
    }

    @Test("a page whose address needs its query to be the same page links to the site, not to a stripped address")
    func functionalQueryPage() {
        let answer = "You searched Search - paris museums on search.example."
        let spans = Linkify.plan(answer: answer, visits: visits, readingList: [])
        #expect(linked(answer, spans) == ["search.example": "https://search.example/"])
    }

    @Test("tracking fields and fragments never reach a link")
    func scrubbedLink() {
        let answer = "Next you opened the Museum pass."
        let spans = Linkify.plan(answer: answer, visits: visits, readingList: [])
        #expect(linked(answer, spans) == ["Museum pass": "https://guide.example/paris/passes"])
    }

    @Test("a host is matched as a whole word: a longer address, an email or a different suffix is not it")
    func hostBoundaries() {
        let answer = "xnews.example, news.example.org, me@news.example and news.example/path are not all the same. See news.example."
        let spans = Linkify.plan(answer: answer, visits: visits, readingList: [])
        #expect(spans.count == 1, "only the first whole-word mention is linked, once per target")
        #expect(answer[spans[0].range] == "news.example")
        #expect(answer[spans[0].range.upperBound...].hasPrefix("/path"), "the path form is the first valid whole-word mention")
    }

    @Test("a mention is linked once, the longer of two overlapping phrases wins")
    func overlapAndOnce() {
        let v = [visit("guide.example Paris notes", "https://guide.example/notes", 1), visit("Other", "https://guide.example/x", 2)]
        let answer = "guide.example Paris notes and guide.example again"
        let spans = Linkify.plan(answer: answer, visits: v, readingList: [])
        #expect(spans.count == 2)
        #expect(String(answer[spans[0].range]) == "guide.example Paris notes")
        #expect(spans[0].url.absoluteString == "https://guide.example/notes")
        #expect(String(answer[spans[1].range]) == "guide.example")
        #expect(spans[0].range.upperBound <= spans[1].range.lowerBound)
    }

    @Test("pages on sensitive topics, other schemes, embedded credentials and hosts without a dot are left out")
    func unsafeCandidates() {
        let v = [visit("Clinic referral", "https://health.example/clinic/referral", 1),
                 visit("Private share", "https://user:pw@secret.example/a", 2),
                 visit("Local file", "file:///tmp/notes.html", 3),
                 visit("Intranet board", "http://localhost/board", 4)]
        let answer = "Clinic referral, Private share, secret.example, Local file, Intranet board, health.example"
        #expect(Linkify.plan(answer: answer, visits: v, readingList: []).isEmpty)
    }

    @Test("the attributed answer carries exactly the planned links and the same text")
    func attributed() {
        let answer = "You read the Local food guide."
        let spans = Linkify.plan(answer: answer, visits: visits, readingList: [])
        let text = Linkify.attributed(answer: answer, spans: spans)
        #expect(String(text.characters) == answer)
        let links = text.runs.compactMap { $0.link }
        #expect(links == [URL(string: "https://guide.example/paris")!])
    }

    @Test("an empty answer or empty evidence plans nothing")
    func empty() {
        #expect(Linkify.plan(answer: "", visits: visits, readingList: reading).isEmpty)
        #expect(Linkify.plan(answer: "Local food guide", visits: [], readingList: []).isEmpty)
    }
}
