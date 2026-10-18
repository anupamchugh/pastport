import Foundation

/// The bounded time window a history question is allowed to use.
///
/// This resolver only filters the visits already supplied by the caller. An
/// unsupported date phrase returns no visits so a question cannot silently
/// widen back to the whole retained snapshot.
public struct HistoryQuestionScope: Sendable {
    public let visits: [Visit]
    public let rangeDescription: String
    public let matchedWindow: Bool
    public let unsupportedReason: String?

    public init(
        visits: [Visit],
        rangeDescription: String,
        matchedWindow: Bool,
        unsupportedReason: String? = nil
    ) {
        self.visits = visits
        self.rangeDescription = rangeDescription
        self.matchedWindow = matchedWindow
        self.unsupportedReason = unsupportedReason
    }

    /// Resolves one of the deliberately small set of supported date phrases.
    ///
    /// Supported forms are `last N days`, `last month`, `last year`, `before
    /// YYYY`, and `during YYYY` / `in YYYY`. Whole-day windows are capped at
    /// 36,500 days to keep parsing and date arithmetic bounded.
    public static func resolve(
        visits: [Visit],
        question: String,
        nowDate: Date = Date(),
        previousScope: HistoryQuestionScope? = nil
    ) -> HistoryQuestionScope {
        let query = question.lowercased()
        var requests: [Request] = []

        for match in matches(Self.lastDaysPattern, in: query) {
            guard let raw = capture(match, in: query) else { continue }
            guard !raw.contains("."), let days = Int(raw), (1...36_500).contains(days) else {
                return unsupported(visits: visits, reason: "Use a whole-number window from 1 to 36500 days.")
            }
            requests.append(.lastDays(days, "last \(days) days"))
        }

        for match in matches(Self.lastNamedPattern, in: query) {
            guard let unit = capture(match, in: query) else { continue }
            requests.append(unit == "month" ? .lastDays(30, "last month (30 days)") : .lastDays(365, "last year (365 days)"))
        }

        for match in matches(Self.beforeYearPattern, in: query) {
            guard let year = validYear(capture(match, in: query)) else {
                return unsupported(visits: visits, reason: "Use a four-digit calendar year.")
            }
            requests.append(.before(year))
        }

        for match in matches(Self.duringYearPattern, in: query) {
            guard let year = validYear(capture(match, in: query)) else {
                return unsupported(visits: visits, reason: "Use a four-digit calendar year.")
            }
            requests.append(.during(year))
        }

        if requests.count > 1 {
            return unsupported(visits: visits, reason: "Use one time window per question.")
        }

        if requests.isEmpty, hasUnsupportedDatePhrase(query) {
            return unsupported(visits: visits, reason: "That date phrase is unsupported; use last N days, last month, last year, before YYYY, during YYYY, or in YYYY.")
        }

        guard let request = requests.first else {
            let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
            let followsPrevious = ["and ", "what about ", "tell me more", "show more", "anything else", "when?", "when was", "when did"].contains { trimmed.hasPrefix($0) }
            let explicitlyAll = ["all retained history", "all history", "entire history", "full history"].contains { trimmed.contains($0) }
            if followsPrevious, !explicitlyAll, let previousScope { return previousScope }
            return HistoryQuestionScope(
                visits: visits,
                rangeDescription: "retained window",
                matchedWindow: !visits.isEmpty
            )
        }

        let calendar = Calendar(identifier: .gregorian)
        let filtered: [Visit]
        let label: String
        switch request {
        case .lastDays(let days, let description):
            let start = nowDate.addingTimeInterval(-Double(days) * 86_400)
            filtered = visits.filter { $0.time >= start && $0.time <= nowDate }
            label = description
        case .before(let year):
            let start = calendar.date(from: DateComponents(year: year, month: 1, day: 1)) ?? .distantFuture
            filtered = visits.filter { $0.time < start }
            label = "before \(year)"
        case .during(let year):
            let start = calendar.date(from: DateComponents(year: year, month: 1, day: 1)) ?? .distantFuture
            let end = calendar.date(from: DateComponents(year: year + 1, month: 1, day: 1)) ?? .distantFuture
            filtered = visits.filter { $0.time >= start && $0.time < end }
            label = "during \(year)"
        }

        return HistoryQuestionScope(
            visits: filtered,
            rangeDescription: label,
            matchedWindow: !filtered.isEmpty
        )
    }
}

private extension HistoryQuestionScope {
    enum Request {
        case lastDays(Int, String)
        case before(Int)
        case during(Int)
    }

    static let lastDaysPattern = try! NSRegularExpression(
        pattern: #"\b(?:last|(?:most\s+)?recent)\s+([0-9]+(?:\.[0-9]+)?)\s+days?\b"#
    )
    static let lastNamedPattern = try! NSRegularExpression(
        pattern: #"\blast\s+(month|year)\b"#
    )
    static let beforeYearPattern = try! NSRegularExpression(
        pattern: #"\bbefore\s+([0-9]{4})\b"#
    )
    static let duringYearPattern = try! NSRegularExpression(
        pattern: #"\b(?:during|in)\s+([0-9]{4})\b"#
    )
    static let yearPattern = try! NSRegularExpression(pattern: #"\b(?:19|20)[0-9]{2}\b"#)
    static let unsupportedLastPattern = try! NSRegularExpression(
        pattern: #"\blast\s+(?:[0-9]+(?:\.[0-9]+)?\s+)?(?:day|days|week|weeks|month|months|year|years)\b"#
    )

    static func matches(_ regex: NSRegularExpression, in text: String) -> [NSTextCheckingResult] {
        regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
    }

    static func capture(_ match: NSTextCheckingResult, in text: String) -> String? {
        guard match.numberOfRanges > 1,
              let range = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[range])
    }

    static func validYear(_ raw: String?) -> Int? {
        guard let raw, let year = Int(raw), (1...9_999).contains(year) else { return nil }
        return year
    }

    static func hasUnsupportedDatePhrase(_ query: String) -> Bool {
        if query.range(of: #"\b(?:today|yesterday|tomorrow|last\s+week|last\s+weeks|last\s+months?|last\s+years?)\b"#, options: .regularExpression) != nil {
            return true
        }
        if matches(unsupportedLastPattern, in: query).isEmpty == false {
            return true
        }
        return matches(yearPattern, in: query).isEmpty == false
    }

    static func unsupported(visits: [Visit], reason: String) -> HistoryQuestionScope {
        HistoryQuestionScope(
            visits: [],
            rangeDescription: "unsupported window",
            matchedWindow: false,
            unsupportedReason: reason
        )
    }
}
