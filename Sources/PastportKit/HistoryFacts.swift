import Foundation

/// An answer worked out in code from the retained visits. The sentence and every number in it
/// come from the data; no model is involved, so it cannot invent a site, a date or a count.
public struct DirectAnswer: Sendable, Equatable {
    public let text: String
    /// Which kind of question this answered, for the receipt.
    public let kind: String
    /// The window the answer covers, so a follow-up can keep it.
    public let scope: String
}

/// Simple factual questions about the history: top sites, how many visits, the last visit to a
/// site, whether something was searched, how many booking-like pages, which places. Anything
/// open-ended ("what was I researching?") is left to the model.
public enum HistoryFacts {
    public static func answer(
        question: String,
        visits: [Visit],
        now: Date = Date(),
        previousScope: HistoryQuestionScope? = nil
    ) -> DirectAnswer? {
        let q = question.lowercased()
        guard let kind = classify(q, visits: visits) else { return nil }

        let scope = HistoryQuestionScope.resolve(visits: visits, question: question, nowDate: now, previousScope: previousScope)
        if let reason = scope.unsupportedReason {
            return DirectAnswer(text: reason, kind: "window", scope: scope.rangeDescription)
        }
        let window = scope.visits
        let label = windowLabel(scope)

        switch kind {
        case .topSites(let limit):
            return topSites(window, limit: limit, label: label, scope: scope)
        case .visitCount:
            let n = window.count
            return DirectAnswer(text: n == 0
                ? "No page visits are saved for \(label)."
                : "\(n) page visit\(n == 1 ? "" : "s") \(inLabel(label)). Counts are page visits, not time spent.",
                kind: "count", scope: scope.rangeDescription)
        case .lastVisit(let target):
            return lastVisit(target, in: window, label: label, scope: scope)
        case .visited(let target):
            return visited(target, in: window, label: label, scope: scope)
        case .searched(let term):
            return searched(term, in: window, label: label, scope: scope)
        case .bookings(let didBook):
            return bookings(window, label: label, didBook: didBook, scope: scope)
        case .places:
            return places(window, label: label, scope: scope)
        }
    }

    // MARK: classification

    enum Kind: Equatable {
        case topSites(Int)
        case visitCount
        case lastVisit(String)
        case visited(String)
        case searched(String)
        case bookings(didBook: Bool)
        case places
    }

    static func classify(_ q: String, visits: [Visit]) -> Kind? {
        func has(_ pattern: String) -> Bool { q.range(of: pattern, options: .regularExpression) != nil }

        if let term = searchTerm(in: q) { return .searched(term) }

        if has(#"\b(?:did|have|had)\s+i\s+(?:ever\s+)?(?:book|booked|reserve|reserved)\b"#) { return .bookings(didBook: true) }
        if has(#"\bhow\s+many\b.*\b(?:booking|bookings|reservation|reservations|itinerar|confirmation|confirmations)"#) { return .bookings(didBook: false) }

        if has(#"\b(?:last|latest|most\s+recent)\b.*\b(?:visit|visited|open|opened|went|go|saw|see|used)\b"#)
            || has(#"\bwhen\s+(?:did|was)\s+i\b.*\b(?:last|latest)\b"#)
            || has(#"\bwhen\s+did\s+i\s+(?:last\s+)?(?:visit|open|use)\b"#),
           let target = target(in: q, visits: visits) { return .lastVisit(target) }

        if has(#"\b(?:did|have|had)\s+i\s+(?:ever\s+)?(?:visit|visited|open|opened|go\s+to|use|used|see|seen)\b"#),
           let target = target(in: q, visits: visits) { return .visited(target) }

        if has(#"\b(?:which|what)\s+places?\b"#) || has(#"\bwhat\s+places\b"#) || has(#"\bplaces\s+(?:appear|show|are|in)\b"#) { return .places }

        if has(#"\btop\s+(?:\d+|one|two|three|four|five|ten)\b"#) || has(#"\bmost\s+(?:visited|often|used|opened)\b"#)
            || has(#"\b(?:visit|visited|open|opened|use|used)\b.*\bmost\b"#) || has(#"\btop\s+(?:site|sites|website|websites)\b"#) {
            guard has(#"\b(?:site|sites|website|websites|domain|domains|page|pages)\b"#) else { return nil }
            return .topSites(topLimit(in: q))
        }

        if has(#"\bhow\s+many\b.*\b(?:visit|visits|visited|page|pages|site|sites|link|links|time|times|tab|tabs)\b"#) { return .visitCount }
        return nil
    }

    static func topLimit(in q: String) -> Int {
        let words = ["one": 1, "two": 2, "three": 3, "four": 4, "five": 5, "ten": 10]
        if let r = q.range(of: #"\btop\s+(\d+|one|two|three|four|five|ten)\b"#, options: .regularExpression) {
            let token = q[r].split(separator: " ").last.map(String.init) ?? "3"
            return min(10, max(1, Int(token) ?? words[token] ?? 3))
        }
        // "most visited site" asks for one; "most visited sites" for a few.
        return q.range(of: #"\b(?:site|website|domain|page)\b"#, options: .regularExpression) != nil
            && q.range(of: #"\b(?:sites|websites|domains|pages)\b"#, options: .regularExpression) == nil ? 1 : 3
    }

    static func searchTerm(in q: String) -> String? {
        guard let r = q.range(of: #"\b(?:search|searched|googled|looked\s+up)\b(?:\s+for)?\s+(.+)$"#, options: .regularExpression),
              q.range(of: #"\b(?:did|have|had)\s+i\b"#, options: .regularExpression) != nil else { return nil }
        var tail = String(q[r])
        tail = tail.replacingOccurrences(of: #"^\b(?:search|searched|googled|looked\s+up)\b(?:\s+for)?\s+"#, with: "", options: .regularExpression)
        tail = tail.replacingOccurrences(of: #"\s+(?:in|during|yesterday|today|last|ever|before)\b.*$"#, with: "", options: .regularExpression)
        let term = tail.trimmingCharacters(in: CharacterSet(charactersIn: " ?.!\"'“”‘’"))
        return term.isEmpty ? nil : term
    }

    /// The site a question names: a full host, or the word before its first dot. A name that
    /// looks like a site but is not in the history comes back as itself, so the answer can say
    /// there is no retained visit to it.
    static func target(in q: String, visits: [Visit]) -> String? {
        let hosts = Set(visits.map(\.host))
        let tokens = q.components(separatedBy: CharacterSet(charactersIn: " ?,!;\"'“”"))
            .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: ".")) }.filter { !$0.isEmpty }
        for token in tokens {
            let bare = token.hasPrefix("www.") ? String(token.dropFirst(4)) : token
            if hosts.contains(bare) { return bare }
        }
        for token in tokens where token.count >= 4 {
            let matches = hosts.filter { $0.split(separator: ".").first.map(String.init) == token }
            if matches.count == 1, let host = matches.first { return host }
        }
        return tokens.first { $0.contains(".") && $0.rangeOfCharacter(from: .letters) != nil && !$0.hasSuffix(".") }
    }

    // MARK: answers

    static func windowLabel(_ scope: HistoryQuestionScope) -> String {
        scope.rangeDescription == "retained window" ? "your history" : scope.rangeDescription
    }

    static func inLabel(_ label: String) -> String {
        switch label {
        case "your history": return "in your history"
        case "today", "yesterday": return label
        default: return label.hasPrefix("last ") || label.hasPrefix("before ") || label.hasPrefix("during ") ? "in the \(label)".replacingOccurrences(of: "in the before", with: "before").replacingOccurrences(of: "in the during", with: "during") : "in \(label)"
        }
    }

    static func day(_ date: Date) -> String { date.formatted(.iso8601.year().month().day()) }

    static func topSites(_ window: [Visit], limit: Int, label: String, scope: HistoryQuestionScope) -> DirectAnswer {
        let counts = Dictionary(grouping: window, by: \.host).mapValues(\.count)
        let ranked = counts.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }.prefix(limit)
        guard !ranked.isEmpty else {
            return DirectAnswer(text: "No page visits are saved for \(label).", kind: "top-sites", scope: scope.rangeDescription)
        }
        let list = ranked.map { "\($0.key) (\($0.value))" }.joined(separator: ", ")
        let head = ranked.count == 1 ? "Most visited site \(inLabel(label))" : "Most visited sites \(inLabel(label))"
        return DirectAnswer(text: "\(head): \(list). Counts are page visits, not time spent.", kind: "top-sites", scope: scope.rangeDescription)
    }

    static func lastVisit(_ target: String, in window: [Visit], label: String, scope: HistoryQuestionScope) -> DirectAnswer {
        let hits = window.filter { $0.host == target }
        guard let last = hits.map(\.time).max() else {
            return DirectAnswer(text: "No visit to \(target) \(inLabel(label)).", kind: "last-visit", scope: scope.rangeDescription)
        }
        return DirectAnswer(text: "Your most recent visit to \(target) was on \(day(last)). It appears \(hits.count) time\(hits.count == 1 ? "" : "s") \(inLabel(label)).",
                            kind: "last-visit", scope: scope.rangeDescription)
    }

    static func visited(_ target: String, in window: [Visit], label: String, scope: HistoryQuestionScope) -> DirectAnswer {
        let hits = window.filter { $0.host == target }
        guard let last = hits.map(\.time).max() else {
            return DirectAnswer(text: "No. There is no retained visit to \(target) \(inLabel(label)).", kind: "visited", scope: scope.rangeDescription)
        }
        return DirectAnswer(text: "Yes. \(target) appears \(hits.count) time\(hits.count == 1 ? "" : "s") \(inLabel(label)); the most recent was \(day(last)).",
                            kind: "visited", scope: scope.rangeDescription)
    }

    static func searched(_ term: String, in window: [Visit], label: String, scope: HistoryQuestionScope) -> DirectAnswer {
        let words = term.components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }
        let hits: [(Date, String)] = window.compactMap { visit in
            guard let query = searchQuery(of: visit) else { return nil }
            let lower = query.lowercased()
            return !words.isEmpty && words.allSatisfy({ lower.contains($0) }) ? (visit.time, query) : nil
        }
        guard let latest = hits.max(by: { $0.0 < $1.0 }) else {
            return DirectAnswer(text: "No. No search page in your history matched “\(term)” \(inLabel(label)).", kind: "searched", scope: scope.rangeDescription)
        }
        return DirectAnswer(text: "Yes. \(hits.count) search page\(hits.count == 1 ? "" : "s") matched “\(term)”; the most recent was on \(day(latest.0)) (“\(latest.1)”).",
                            kind: "searched", scope: scope.rangeDescription)
    }

    /// The typed query of a search-results page: from "… - Google Search" or "… - Search", or the q= parameter.
    static func searchQuery(of visit: Visit) -> String? {
        if let q = Threads.query(fromTitle: visit.title) { return q }
        if visit.title.hasSuffix(" - Search"), let r = visit.title.range(of: " - Search", options: .backwards) {
            let q = visit.title[..<r.lowerBound].trimmingCharacters(in: .whitespaces)
            if !q.isEmpty { return q }
        }
        if let items = URLComponents(string: visit.url)?.queryItems,
           let q = items.first(where: { ["q", "query", "search_query"].contains($0.name) })?.value, !q.isEmpty,
           visit.url.contains("search") { return q }
        return nil
    }

    static func bookings(_ window: [Visit], label: String, didBook: Bool, scope: HistoryQuestionScope) -> DirectAnswer {
        let found = Bookings.scan(from: window)
        let travel = found.filter(\.isTravel)
        let caveat = "A page in your history shows it was opened; it does not prove anything was bought or completed."
        if found.isEmpty {
            return DirectAnswer(text: "I found no booking-like pages \(inLabel(label)). \(didBook ? "History cannot confirm a booking either way." : "")".trimmingCharacters(in: .whitespaces),
                                kind: "bookings", scope: scope.rangeDescription)
        }
        let examples = found.sorted { $0.time > $1.time }.prefix(3).map { "\(day($0.time)): \($0.title.isEmpty ? $0.host : $0.title)" }.joined(separator: "; ")
        let lead = didBook ? "I can’t tell whether you booked. " : ""
        return DirectAnswer(text: "\(lead)I found \(found.count) booking-like page\(found.count == 1 ? "" : "s") \(inLabel(label)) (\(travel.count) travel-related): \(examples). \(caveat)",
                            kind: "bookings", scope: scope.rangeDescription)
    }

    static func places(_ window: [Visit], label: String, scope: HistoryQuestionScope) -> DirectAnswer {
        var seen = Set<String>(); var names: [String] = []
        for place in Movements.scan(from: window).compactMap(\.place) where seen.insert(place).inserted { names.append(place) }
        guard !names.isEmpty else {
            return DirectAnswer(text: "No named place appears in the map links \(inLabel(label)).", kind: "places", scope: scope.rangeDescription)
        }
        return DirectAnswer(text: "Map links \(inLabel(label)) name: \(names.prefix(6).joined(separator: ", ")). These come from map addresses in your history; they do not show you were there.",
                            kind: "places", scope: scope.rangeDescription)
    }
}
