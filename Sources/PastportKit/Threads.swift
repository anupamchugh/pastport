import Foundation

/// A stretch of browsing where the person was *trying to work something out* — a burst of
/// related searches plus the sites they landed on. Unlike `LocationLeak`, nothing here is
/// leaked by a tracker; the signal is the person's own words, typed into a search box and
/// preserved in the page title. That is what makes a trip, a purchase decision, or a legal
/// worry legible weeks later.
public struct IntentThread: Identifiable, Finding {
    public let id = UUID()
    public let term: String          // the anchor term — the one that burst
    public let related: [String]     // terms that co-occurred with it
    public let queries: [String]     // the person's own phrasing, verbatim
    public let started: Date
    public let destinations: [String]  // non-search hosts visited inside the window
    public let searchCount: Int

    public init(term: String, related: [String], queries: [String], started: Date,
                destinations: [String], searchCount: Int) {
        self.term = term
        self.related = related
        self.queries = queries
        self.started = started
        self.destinations = destinations
        self.searchCount = searchCount
    }

    /// Stable identity for "have I already told you about this?" — anchor plus start day.
    public var key: String {
        "\(term)|\(started.formatted(.iso8601.year().month().day()))"
    }

    public var notificationBody: String {
        queries.first ?? destinations.joined(separator: ", ")
    }

    /// A deterministic one-line label. No model, no invented nouns — the person's own
    /// vocabulary plus a date, so this line can never be wrong.
    public var headline: String {
        let when = started.formatted(.dateTime.month(.abbreviated).day())
        return "\(when): \(([term] + related).joined(separator: ", "))"
    }

    /// Whether this thread should be hidden until the person asks to see it.
    ///
    /// Not a privacy claim about the data — everything here is equally private. It is a
    /// *shoulder-surfing* judgement: some topics you would not want rendered on a laptop
    /// in a café, and the topic word alone is enough to expose them — a card reading
    /// "clinic, referral" or "lawyer, custody" has already said the thing it was meant to
    /// protect. That is why a locked card shows neither the topic nor the count.
    ///
    /// This list is a deliberate exception to the no-word-lists rule elsewhere in the
    /// package: it protects the person rather than classifying the world, it is short, and
    /// it is meant to be edited by whoever disagrees with it.
    public var isSensitive: Bool {
        let markers = [
            // health
            "chair", "assistance", "fracture", "symptom", "diagnos", "clinic", "doctor",
            "therapy", "medication", "disorder", "cancer", "pregnan", "abortion", "mental",
            "disabilit", "surgery", "prescription",
            // intimate
            "porn", "nsfw", "escort", "sexual",
            // distress
            "lawyer", "arrest", "bail", "debt", "bankrupt", "divorce", "custody",
        ]
        let haystack = ([term] + related + queries).joined(separator: " ").lowercased()
        return markers.contains { haystack.contains($0) }
    }

    /// One line for the monthly digest. Lives here so the CLI and the app can't drift.
    public var digestLine: String {
        "\(headline) — \(queries.prefix(3).joined(separator: "; "))"
    }

    /// Compact lines for a model prompt. Kept tiny on purpose — one thread is meant to fit
    /// a session with room to spare (the on-device window is 4096 tokens per session).
    public var promptLines: String {
        var out = queries.prefix(6).map { "  searched: \($0)" }
        if !destinations.isEmpty {
            out.append("  visited: \(destinations.prefix(5).joined(separator: ", "))")
        }
        return out.joined(separator: "\n")
    }
}

/// Deterministic extraction of intent threads. No model, no topic taxonomy, no domain list —
/// topics emerge from what the person actually typed, and destinations from where they landed.
///
/// The one structural assumption is a title convention every search engine shares:
/// `<what you typed> - <Engine> Search`. No engine is named anywhere in this file.
public enum Threads {

    // MARK: - thresholds the tests exercise

    /// A term must be searched at least this many times to be a candidate.
    static let minSearches = 3
    /// searches ÷ days-spanned. Below this a term is evergreen (a habit), not a decision.
    /// This is what demotes a term searched 9,000 times a year down to noise.
    static let minConcentration = 0.25
    /// Two terms join one thread if they appear together in at least this many queries.
    static let minCoOccurrence = 2

    /// Words too common to anchor a thread. Deliberately generic — no topics, no brands.
    static let stopWords: Set<String> = [
        "the", "and", "for", "with", "what", "how", "why", "best", "near", "new",
        "from", "that", "this", "into", "your", "when", "where", "which", "does",
        "have", "been", "about", "will", "should", "could", "would", "there",
        "online", "free", "full", "like", "vs", "review", "reviews",
    ]

    // MARK: - extraction

    /// `"kyoto has separate visa? - Google Search"` → `"kyoto has separate visa?"`.
    /// Matches any engine that follows the `… - <Word> Search` title convention.
    static let queryPattern = try? NSRegularExpression(
        pattern: #"^(.*?)\s+[-–|]\s+\w+\s+Search$"#, options: [.caseInsensitive]
    )

    /// Inverting a CharacterSet allocates a bitmap, so build it once rather than per query.
    static let wordSeparators = CharacterSet.alphanumerics.inverted

    /// Pull the typed query out of a page title, or nil if this wasn't a search results page.
    static func query(fromTitle title: String) -> String? {
        // Cheap gate first. The pattern can only match a title ending in "Search", and a
        // history is >95% non-search pages — this skips the NSString bridge and the lazy
        // quantifier's backtracking for ~290k of 300k rows.
        guard title.hasSuffix("Search") || title.hasSuffix("search") else { return nil }
        guard let re = queryPattern else { return nil }
        let range = NSRange(title.startIndex..., in: title)
        guard let m = re.firstMatch(in: title, range: range),
              let r = Range(m.range(at: 1), in: title) else { return nil }
        let q = title[r].trimmingCharacters(in: .whitespacesAndNewlines)
        return q.isEmpty ? nil : q
    }

    /// Content words worth indexing: >3 characters, not a stop word, not a bare number.
    static func terms(in query: String) -> Set<String> {
        Set(
            query.lowercased()
                .components(separatedBy: wordSeparators)
                .filter { $0.count > 3 && !stopWords.contains($0) && Int($0) == nil }
        )
    }

    /// Whole days spanned by a burst, floored at 1 so a single-day burst doesn't divide by zero.
    static func daysSpanned(_ from: Date, _ to: Date) -> Double {
        let days = Calendar.current.dateComponents([.day], from: from, to: to).day ?? 0
        return Double(max(days, 0)) + 1
    }

    // MARK: - main

    public static func scan(from visits: [Visit], limit: Int = 12) -> [IntentThread] {
        // One pass: split visits into searches (intent) and everything else (destinations).
        // Hosts that produced a search-titled page are search engines — identified by
        // behaviour, never by name — so they can't pollute the destination list.
        var searches: [(time: Date, query: String, terms: Set<String>)] = []
        var searchHosts = Set<String>()
        var others: [(time: Date, host: String)] = []

        for visit in visits {
            // `Visit.host` parses a URLComponents on every access — bind it once.
            let host = visit.host
            if let q = query(fromTitle: visit.title) {
                let t = terms(in: q)
                searchHosts.insert(host)
                if !t.isEmpty { searches.append((visit.time, q, t)) }
            } else if !host.isEmpty {
                others.append((visit.time, host))
            }
        }
        guard !searches.isEmpty else { return [] }
        searches.sort { $0.time < $1.time }

        // Drop engines once, rather than re-testing every row inside the per-thread loop.
        others.removeAll { searchHosts.contains($0.host) }

        // Index each term to the *positions* of the searches it appeared in. Indices rather
        // than copies: `searches` already holds the time, the query, and the parsed terms,
        // so nothing needs re-tokenizing later. Sorting `searches` first means every one of
        // these arrays is already in ascending time order.
        var hits: [String: [Int]] = [:]
        for (i, s) in searches.enumerated() {
            for term in s.terms { hits[term, default: []].append(i) }
        }

        // A candidate is a term searched often AND in a tight window. Concentration is the
        // whole trick: it separates "a thing I looked into" from "a thing I always look at".
        var candidates: [(score: Double, term: String)] = []
        for (term, positions) in hits where positions.count >= minSearches {
            let first = searches[positions[0]].time
            let last = searches[positions[positions.count - 1]].time
            let concentration = Double(positions.count) / daysSpanned(first, last)
            guard concentration >= minConcentration else { continue }
            candidates.append((Double(positions.count) * concentration, term))
        }
        candidates.sort { $0.score > $1.score }

        // Merge co-occurring terms into one thread so `kyoto` and `visa` don't become two
        // findings. Highest-scoring term claims its partners; they can't anchor their own.
        var claimed = Set<String>()
        var threads: [IntentThread] = []

        for candidate in candidates {
            if threads.count >= limit { break }
            guard !claimed.contains(candidate.term), let positions = hits[candidate.term] else { continue }

            // Terms were parsed once during indexing, so this reads them rather than
            // re-tokenizing every query a second time.
            var partnerCounts: [String: Int] = [:]
            for i in positions {
                for other in searches[i].terms where other != candidate.term {
                    partnerCounts[other, default: 0] += 1
                }
            }
            let partners = partnerCounts.filter { $0.value >= minCoOccurrence }.map(\.key).sorted()

            claimed.insert(candidate.term)
            claimed.formUnion(partners)

            // People search, then browse — so look slightly before the first search and
            // well after the last one for where they actually landed.
            let started = searches[positions[0]].time
            let window = started.addingTimeInterval(-20 * 60)
                ... searches[positions[positions.count - 1]].time.addingTimeInterval(6 * 3600)

            var destCounts: [String: Int] = [:]
            for o in others where window.contains(o.time) {
                destCounts[o.host, default: 0] += 1
            }
            let destinations = destCounts.sorted { $0.value > $1.value }.prefix(6).map(\.key)

            // Dedupe queries while preserving the order they were typed in.
            var seenQueries = Set<String>()
            let queries = positions.map { searches[$0].query }.filter { seenQueries.insert($0).inserted }

            threads.append(IntentThread(
                term: candidate.term, related: Array(partners.prefix(2)), queries: queries,
                started: started, destinations: destinations, searchCount: positions.count
            ))
        }

        return threads.sorted { $0.started > $1.started }
    }

    // MARK: - narration

    /// Prompt for a single thread. Deliberately small — one thread per session, so each gets
    /// a full context window instead of sharing one (see TN3193).
    ///
    /// The place-name rule matters: the model has no geocoder and no world knowledge it can
    /// safely apply here, so it must not name anywhere the person didn't type.
    public static func narrationPrompt(for thread: IntentThread, instruction: String? = nil) -> String {
        let steer = instruction.map { "\nThe person asked you to: \($0)\n" } ?? ""
        return """
        Below is one stretch of a person's own web browsing: what they searched, and where
        they landed. Say in one sentence what they were trying to work out, and in one more
        what it reveals that they might not have realised was recorded.

        Use ONLY the words below. Never name a place, company, or product that does not
        appear verbatim. If you infer, say you are inferring.
        \(steer)
        \(thread.promptLines)
        """
    }
}
