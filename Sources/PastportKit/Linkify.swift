import Foundation

/// One link planned inside an answer: the words to link and where they go.
public struct LinkSpan: Sendable, Equatable {
    public enum Kind: Sendable, Equatable {
        /// A site the person visited; the link is that site's front page.
        case site
        /// One page the person visited, by its title.
        case page
        /// An item on the person's Reading List, by its title.
        case readingList
    }

    /// The linked words, as a range of the answer that was planned.
    public let range: Range<String.Index>
    public let url: URL
    public let kind: Kind
}

/// Plans the links in an answer. The only link targets are sites, pages and Reading List items that are already in
/// the person's own evidence, so a name in an answer that the evidence does not hold (a place, a person, a topic) is
/// never linked, and no link is ever a web search. Pure code: no model, no network, nothing stored. The host app
/// decides what a tap does; opening a page should go through the same "contact this site" confirmation as any
/// evidence link.
public enum Linkify {
    private struct Candidate {
        let phrase: String
        let url: URL
        let kind: LinkSpan.Kind
    }

    private struct Match {
        let range: Range<String.Index>
        let candidate: Candidate
    }

    public static func plan(answer: String, visits: [Visit], readingList: [ReadingListItem]) -> [LinkSpan] {
        guard !answer.isEmpty else { return [] }
        var matches: [Match] = []
        for candidate in candidates(visits: visits, readingList: readingList) {
            var from = answer.startIndex
            while from < answer.endIndex,
                  let found = answer.range(of: candidate.phrase, options: [.caseInsensitive], range: from..<answer.endIndex) {
                if isWholeMention(found, in: answer, host: candidate.kind == .site) {
                    matches.append(Match(range: found, candidate: candidate))
                }
                from = found.upperBound
            }
        }
        // The longest phrase wins an overlap; among equals the earliest mention does.
        matches.sort {
            let (a, b) = (answer.distance(from: $0.range.lowerBound, to: $0.range.upperBound),
                          answer.distance(from: $1.range.lowerBound, to: $1.range.upperBound))
            return a != b ? a > b : $0.range.lowerBound < $1.range.lowerBound
        }
        var chosen: [Match] = []
        var linkedTargets = Set<URL>()
        for match in matches {
            guard !linkedTargets.contains(match.candidate.url),
                  !chosen.contains(where: { $0.range.overlaps(match.range) }) else { continue }
            chosen.append(match)
            linkedTargets.insert(match.candidate.url)
        }
        return chosen.sorted { $0.range.lowerBound < $1.range.lowerBound }
            .map { LinkSpan(range: $0.range, url: $0.candidate.url, kind: $0.candidate.kind) }
    }

    /// The answer as styled text with the planned links attached.
    public static func attributed(answer: String, spans: [LinkSpan]) -> AttributedString {
        var text = AttributedString(answer)
        for span in spans {
            guard let lower = AttributedString.Index(span.range.lowerBound, within: text),
                  let upper = AttributedString.Index(span.range.upperBound, within: text) else { continue }
            text[lower..<upper].link = span.url
        }
        return text
    }

    // MARK: Candidates

    private static func candidates(visits: [Visit], readingList: [ReadingListItem]) -> [Candidate] {
        var hosts: [String: URL] = [:]
        var titles: [String: (urls: Set<URL>, first: Candidate)] = [:]

        func addTitle(_ title: String, url: URL, host: String, kind: LinkSpan.Kind) {
            let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.count >= 4, trimmed.lowercased() != host else { return }
            let key = trimmed.lowercased()
            if var entry = titles[key] {
                entry.urls.insert(url); titles[key] = entry
            } else {
                titles[key] = ([url], Candidate(phrase: trimmed, url: url, kind: kind))
            }
        }

        for visit in visits {
            guard let page = pageURL(visit.url, title: visit.title) else { continue }
            let host = visit.host
            if let front = URL(string: "https://\(host)/") { hosts[host] = front }
            if page.isPlain { addTitle(visit.title, url: page.url, host: host, kind: .page) }
        }
        for item in readingList {
            guard let page = pageURL(item.url, title: item.title) else { continue }
            let host = item.host
            if page.isPlain { addTitle(item.title, url: page.url, host: host, kind: .readingList) }
        }
        let sites = hosts.map { Candidate(phrase: $0.key, url: $0.value, kind: .site) }
        // A title that two different addresses share is ambiguous, so it is not linked.
        let pages = titles.values.filter { $0.urls.count == 1 }.map(\.first)
        return sites + pages
    }

    /// The scrubbed address of a page the person has, or nil when it is not a plain web page or is a sensitive topic.
    /// `isPlain` is false when the page's identity lives in its query (a search), so only its site may be linked.
    private static func pageURL(_ raw: String, title: String) -> (url: URL, isPlain: Bool)? {
        guard var parts = URLComponents(string: raw),
              let scheme = parts.scheme?.lowercased(), scheme == "http" || scheme == "https",
              parts.user == nil, parts.password == nil,
              let host = parts.host, host.contains("."),
              !SensitiveTopics.matches(title + " " + raw) else { return nil }
        let functional = (parts.queryItems ?? []).contains { item in
            let name = item.name.lowercased()
            return !(name.hasPrefix("utm_") || ["fbclid", "gclid", "mc_eid"].contains(name))
        }
        parts.query = nil; parts.fragment = nil
        guard let url = parts.url else { return nil }
        return (url, !functional)
    }

    // MARK: Boundaries

    private static func isWholeMention(_ range: Range<String.Index>, in text: String, host: Bool) -> Bool {
        let before: Character? = range.lowerBound > text.startIndex ? text[text.index(before: range.lowerBound)] : nil
        let after: Character? = range.upperBound < text.endIndex ? text[range.upperBound] : nil
        func word(_ c: Character?) -> Bool { c.map { $0.isLetter || $0.isNumber } ?? false }
        guard !word(before), !word(after) else { return false }
        guard host else { return true }
        if let before, "-.@".contains(before) { return false }
        if let after {
            if after == "-" { return false }
            if after == "." {
                let next = text.index(after: range.upperBound)
                if next < text.endIndex, word(text[next]) { return false }
            }
        }
        return true
    }
}
