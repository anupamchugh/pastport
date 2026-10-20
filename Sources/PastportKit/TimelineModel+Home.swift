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

    /// Research topics that are safe to name on screen. Sensitive topics stay behind authentication.
    public var nameableThreads: [IntentThread] { threads.filter { !$0.isSensitive } }

    /// A few questions the data in hand can actually answer, so the first tap works.
    public var starterQuestions: [String] {
        var starters: [String] = []
        if historyLoaded {
            if !travel.isEmpty { starters.append("How many booking pages did I visit?") }
            if !movements.isEmpty { starters.append("Which places appear in my history?") }
            if !sites.isEmpty { starters.append("Which sites do I visit most?") }
            starters.append("How many pages did I visit yesterday?")
            if !nameableThreads.isEmpty { starters.append("What was I researching?") }
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

    /// The findings that have something to show, in the order a person cares about.
    public var focusCards: [FocusCard] {
        var cards: [FocusCard] = []
        func inflected(_ text: AttributedString) -> String { String(text.characters) }
        func day(_ d: Date) -> String { d.formatted(.dateTime.month(.abbreviated).day()) }
        if !travel.isEmpty {
            let latest = travel.max { $0.time < $1.time }
            let n = travel.count
            cards.append(FocusCard(
                focus: .travel, title: "Trips and bookings",
                headline: inflected(AttributedString(localized: "^[\(n) booking page](inflect: true)")),
                detail: latest.map { "Latest: " + ($0.title.isEmpty ? Bookings.name(for: $0.host) : $0.title) + ", " + day($0.time) } ?? "",
                symbol: "airplane", tint: .orange))
        }
        let places = Array(NSOrderedSet(array: movements.compactMap(\.place))) as? [String] ?? []
        if !places.isEmpty {
            cards.append(FocusCard(
                focus: .places, title: "Places",
                headline: places.prefix(2).joined(separator: ", ") + (places.count > 2 ? " and \(places.count - 2) more" : ""),
                detail: "From map links in your history. A link does not mean you went there.",
                symbol: "mappin.and.ellipse", tint: .red))
        }
        // Only topics that are safe to show. A sensitive topic shows neither its name nor its count.
        let named = nameableThreads
        if let first = named.first {
            let n = named.count
            cards.append(FocusCard(
                focus: .research, title: "What you looked into",
                headline: ([first.term] + first.related).joined(separator: ", ").capitalized,
                detail: n > 1 ? inflected(AttributedString(localized: "^[\(n) topic](inflect: true) in all")) : "",
                symbol: "magnifyingglass", tint: .teal))
        }
        if let top = sites.first {
            cards.append(FocusCard(
                focus: .overview, title: "Most visited",
                headline: top.host,
                detail: sites.dropFirst().isEmpty
                    ? "\(top.visits) visits"
                    : "\(top.visits) visits, then " + sites.dropFirst().prefix(2).map(\.host).joined(separator: ", "),
                symbol: "safari", tint: .blue))
        }
        if !trackerSignals.isEmpty {
            let n = trackerSignals.count
            cards.append(FocusCard(
                focus: .privacy, title: "Trackers",
                headline: inflected(AttributedString(localized: "^[\(n) tracking pattern](inflect: true)")),
                detail: "Links that can follow a click from one site to another.",
                symbol: "eye.slash", tint: .purple))
        }
        return cards
    }
}
