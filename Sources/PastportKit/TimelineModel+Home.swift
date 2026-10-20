import Foundation
import SwiftUI

/// What the home screen and the Ask empty state need, in plain terms.
extension TimelineModel {
    /// True once anything has been read: Safari history (Mac), photo activity or an added screenshot.
    public var hasContent: Bool { historyLoaded || !photoEvents.isEmpty || !screenshots.isEmpty }

    /// The status line worth showing on the welcome screen: what went wrong or changed, not the idle text.
    public var attentionStatus: String? {
        let idle = ["History is closed", "Your timeline is closed", "Model discovery"]
        guard !status.isEmpty, !idle.contains(where: { status.hasPrefix($0) }) else { return nil }
        return status
    }

    /// Pages in the read history whose title or address contains every word, newest first.
    public func search(_ text: String, limit: Int = 40) -> [Visit] {
        let words = text.lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }
        guard !words.isEmpty else { return [] }
        var seen = Set<String>()
        var found: [Visit] = []
        for visit in visits.sorted(by: { $0.time > $1.time }) {
            let haystack = (visit.title + " " + visit.cleanURL).lowercased()
            guard words.allSatisfy({ haystack.contains($0) }), seen.insert(visit.cleanURL).inserted else { continue }
            found.append(visit)
            if found.count == limit { break }
        }
        return found
    }

    /// Research topics that are safe to name on screen. Sensitive topics stay behind authentication.
    public var nameableThreads: [IntentThread] { threads.filter { !$0.isSensitive } }

    /// A few questions the data in hand can actually answer, so the first tap works.
    public var starterQuestions: [String] {
        var starters: [String] = []
        if historyLoaded {
            if !sites.isEmpty { starters.append("Which sites do I visit most?") }
            starters.append("How many pages did I visit yesterday?")
            if !nameableThreads.isEmpty { starters.append("What was I researching?") }
            if !movements.isEmpty { starters.append("Which places appear in my history?") }
            if !travel.isEmpty { starters.append("How many booking pages did I visit?") }
        } else {
            if !photoEvents.isEmpty { starters.append("What does my photo activity show?") }
            if !screenshots.isEmpty { starters.append("What does my screenshot say?") }
        }
        return Array(starters.prefix(4))
    }
}

extension TimelineModel {
    /// One finding on the home screen.
    public struct FocusCard: Identifiable {
        public let focus: HistoryFocus
        public let title: String
        public let headline: String
        public let detail: String
        public let symbol: String
        public let tint: Color
        public var id: HistoryFocus { focus }
    }

    /// The findings that have something to show. General jobs come first; trips are one card among them.
    public var focusCards: [FocusCard] {
        var cards: [FocusCard] = []
        func inflected(_ text: AttributedString) -> String { String(text.characters) }
        func day(_ d: Date) -> String { d.formatted(.dateTime.month(.abbreviated).day()) }

        // What you have been into: research topics, and the sites you used most this week.
        let weekStart = Date().addingTimeInterval(-7 * 86_400)
        var weekCounts: [String: Int] = [:]
        for visit in visits where visit.time >= weekStart { weekCounts[visit.host, default: 0] += 1 }
        let weekRanked = weekCounts.sorted { a, b in a.value != b.value ? a.value > b.value : a.key < b.key }
        let weekHosts: [String] = weekRanked.prefix(3).map { $0.key }
        // A sensitive topic shows neither its name nor its count.
        let named = nameableThreads
        var topic: String?
        if let first = named.first { topic = ([first.term] + first.related).joined(separator: ", ").capitalized }
        if topic != nil || !sites.isEmpty {
            var detailParts: [String] = []
            if named.count > 1 {
                let extra = named.count - 1
                detailParts.append(inflected(AttributedString(localized: "^[\(extra) more topic](inflect: true)")))
            }
            let usingWeek = !weekHosts.isEmpty
            let hosts: [String] = usingWeek ? weekHosts : sites.prefix(3).map { $0.host }
            if !hosts.isEmpty {
                detailParts.append((usingWeek ? "This week: " : "Most visited: ") + hosts.joined(separator: ", "))
            }
            let headline: String = topic ?? (sites.first?.host ?? "")
            cards.append(FocusCard(
                focus: .research, title: "What you've been into", headline: headline,
                detail: detailParts.joined(separator: " · "), symbol: "sparkles", tint: .teal))
        }

        // Privacy check: trackers, and links that carry a location.
        let t = trackerSignals.count, m = movements.count
        let privacyHeadline: String
        if t == 0 && m == 0 {
            privacyHeadline = "Nothing concerning found"
        } else {
            let trackers = inflected(AttributedString(localized: "^[\(t) tracker](inflect: true)"))
            let links = inflected(AttributedString(localized: "^[\(m) link](inflect: true) with a location"))
            privacyHeadline = [t > 0 ? trackers : nil, m > 0 ? links : nil].compactMap { $0 }.joined(separator: ", ")
        }
        cards.append(FocusCard(
            focus: .privacy, title: "Privacy check", headline: privacyHeadline,
            detail: "Trackers follow a click between sites. A map link in your history does not mean you went there.",
            symbol: "hand.raised", tint: .purple))

        if !travel.isEmpty {
            let latest = travel.max { $0.time < $1.time }
            let n = travel.count
            cards.append(FocusCard(
                focus: .travel, title: "Trips and bookings",
                headline: inflected(AttributedString(localized: "^[\(n) booking page](inflect: true)")),
                detail: latest.map { "Latest: " + ($0.title.isEmpty ? Bookings.name(for: $0.host) : $0.title) + ", " + day($0.time) } ?? "",
                symbol: "airplane", tint: .orange))
        }
        return cards
    }
}
