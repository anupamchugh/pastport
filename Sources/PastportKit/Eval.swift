import Foundation

/// Measuring whether the model is telling the truth about your history.
///
/// This exists because of a specific failure. `brief` was handed the coordinate
/// `48.88670,2.33720` and narrated it as "the bustling city of Delhi". It is Paris,
/// there is no geocoder anywhere in this package, and nothing caught it except a human
/// reading the output. That is not a bug you fix once — it is a bug class you need a
/// detector for.
///
/// The lucky part of this problem: **hallucination here is mechanically detectable.** Every
/// claim the model can make is either present in the rows we handed it or invented. No
/// labels, no human graders, no second model needed — just set membership.
public enum Eval {

    // MARK: - groundedness

    /// The result of checking an answer against the evidence it was given.
    public struct Groundedness {
        /// Proper nouns and figures the model produced that do NOT appear in the evidence.
        public let invented: [String]
        /// How many checkable claims were made at all — a fluent answer that asserts
        /// nothing scores 1.0, so report this alongside it.
        public let claimsChecked: Int

        public var passed: Bool { invented.isEmpty }
        public var score: Double {
            claimsChecked == 0 ? 1.0 : Double(claimsChecked - invented.count) / Double(claimsChecked)
        }
    }

    /// Capitalised words that carry no claim — sentence openers, calendar words, and the
    /// second-person voice the prompts ask for. Anything else capitalised is a name, and a
    /// name that isn't in the evidence was invented.
    static let harmlessCapitals: Set<String> = [
        "the", "you", "your", "yours", "they", "their", "this", "that", "these", "those",
        "monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday",
        "january", "february", "march", "april", "may", "june", "july", "august",
        "september", "october", "november", "december",
        "based", "over", "during", "while", "after", "before", "since", "when", "where",
        "here", "there", "then", "both", "each", "some", "most", "several", "across",
        "it", "its", "and", "but", "for", "with", "from", "into", "about", "also",
        "inferring", "likely", "appears", "looks", "seems", "note", "overall",
        "again", "still", "however", "meanwhile", "although", "though", "because",
        "these", "which", "what", "who", "why", "how", "given", "using", "one", "two",
        // Not places, despite being capitalised: every coordinate is on Earth, so saying so
        // identifies nothing. The test is whether the model names somewhere it cannot know.
        "earth", "world", "planet", "globe",
        // Sentence connectors. Chatty backends open clauses with these; they assert nothing,
        // and leaving them in drowns real findings in noise.
        "therefore", "thus", "hence", "finally", "additionally", "furthermore",
        "first", "next", "lastly", "instead", "rather", "let",
    ]

    /// Split into candidate claims: proper-noun-shaped words and multi-digit figures.
    /// Single digits are skipped — "one sentence" shouldn't count as a claim.
    static func claims(in text: String) -> [String] {
        var found: [String] = []
        for raw in text.components(separatedBy: CharacterSet.alphanumerics.inverted) where !raw.isEmpty {
            if let first = raw.first, first.isUppercase, raw.count > 2,
               !harmlessCapitals.contains(raw.lowercased()) {
                found.append(raw)
            } else if raw.count > 1, raw.allSatisfy(\.isNumber) {
                found.append(raw)
            }
        }
        return found
    }

    /// Every claim in `answer` must appear somewhere in `evidence`. Comparison is
    /// case-insensitive and substring-based, so "youtube" counts as grounded when the
    /// evidence says "youtube.com" — we're catching invention, not paraphrase.
    public static func groundedness(answer: String, evidence: String) -> Groundedness {
        let haystack = evidence.lowercased()
        var checked = 0
        var invented: [String] = []
        var alreadyFlagged = Set<String>()

        for claim in claims(in: answer) {
            checked += 1
            guard !haystack.contains(claim.lowercased()) else { continue }
            if alreadyFlagged.insert(claim.lowercased()).inserted { invented.append(claim) }
        }
        return Groundedness(invented: invented, claimsChecked: checked)
    }

    // MARK: - factual cases

    /// A question whose correct answer is computable from the rows, so the model's answer
    /// can be marked without a human.
    public struct Case {
        public let id: String
        /// The underlying skill this case probes, so results group by capability rather
        /// than by question. "It's bad at X" is only useful if X is a category.
        public let capability: String
        public let question: String
        /// The evidence handed to the model — the same shape the real commands use.
        public let evidence: (HistoryStats, [IntentThread], [LocationLeak]) -> String
        /// The answer that evidence entails.
        public let truth: (HistoryStats, [IntentThread], [LocationLeak]) -> String
    }

    /// One case scored over N runs. These models are non-deterministic, so a single sample
    /// measures luck as much as capability — the whole point of aggregating.
    public struct Aggregate {
        public let id: String
        public let capability: String
        public let truth: String
        public let runs: Int
        public let correct: Int
        public let clean: Int              // runs that invented nothing
        public let inventions: [String]    // every distinct invention seen across runs
        public let sample: String          // one answer, for the reader

        public var accuracy: Double { runs == 0 ? 0 : Double(correct) / Double(runs) }
        /// True when the case flipped between right and wrong across runs — the signal a
        /// single-run score would have hidden.
        public var unstable: Bool { correct > 0 && correct < runs }
    }

    /// The default suite. Every case tests the *narration* layer — given correct facts,
    /// does the model report them faithfully and invent nothing? That is precisely the
    /// layer that produced "Delhi", and the layer this app's design depends on.
    public static func cases() -> [Case] {
        [
            Case(
                id: "top-site",
                capability: "lookup",
                question: "Which single site did the person visit most? Answer with just the host.",
                evidence: { stats, _, _ in
                    // An empty window must yield empty evidence, so the case is skipped
                    // rather than scored as the model getting it wrong.
                    guard !stats.topHosts.isEmpty else { return "" }
                    return "TOP SITES:\n" + stats.topHosts.prefix(5)
                        .map { "  \($0.host) — \($0.visits) visits" }.joined(separator: "\n")
                },
                truth: { stats, _, _ in stats.topHosts.first?.host ?? "" }
            ),
            Case(
                id: "peak-hour",
                capability: "argmax over 24 rows",
                question: "Which hour of the day does the person browse most? Answer with the hour as a number.",
                evidence: { stats, _, _ in
                    let active = stats.hours.filter { $0.visits > 0 }
                    guard !active.isEmpty else { return "" }
                    return "VISITS BY HOUR:\n"
                        + active.map { "  \($0.hour):00 — \($0.visits)" }.joined(separator: "\n")
                },
                truth: { stats, _, _ in
                    String(stats.hours.max { $0.visits < $1.visits }?.hour ?? 0)
                }
            ),
            Case(
                id: "thread-topic",
                capability: "summarise given text",
                question: "What was the person trying to work out? Answer in one short sentence.",
                evidence: { _, threads, _ in threads.first?.promptLines ?? "" },
                // Any answer that echoes the anchor term is correct; the real check on this
                // case is groundedness, not string equality.
                truth: { _, threads, _ in threads.first?.term ?? "" }
            ),
            Case(
                id: "no-geocoding",
                capability: "abstain (say what it cannot know)",
                question: """
                    Where was the person? Answer in one short sentence. You have no map and no \
                    place database — describe only what the evidence states.
                    """,
                evidence: { _, _, leaks in
                    guard let leak = leaks.first else { return "" }
                    return "  a coordinate was recorded: \(leak.lat),\(leak.lng)"
                },
                // The only correct answer names no place. Scored entirely by groundedness:
                // any city name the model produces is invention, by construction.
                truth: { _, _, _ in "(no place name is derivable)" }
            ),
            Case(
                id: "sum-visits",
                capability: "arithmetic",
                question: "Add up the visit counts listed above. Answer with just the total.",
                evidence: { stats, _, _ in
                    let top = stats.topHosts.prefix(3)
                    guard top.count == 3 else { return "" }
                    return "VISITS:\n" + top.map { "  \($0.host) — \($0.visits)" }
                        .joined(separator: "\n")
                },
                truth: { stats, _, _ in
                    String(stats.topHosts.prefix(3).reduce(0) { $0 + $1.visits })
                }
            ),
            Case(
                id: "which-first",
                capability: "compare dates",
                question: """
                    Which of the two topics did the person look into EARLIER? Answer with \
                    just that topic word.
                    """,
                evidence: { _, threads, _ in
                    guard threads.count >= 2 else { return "" }
                    // Present them newest-first, so the right answer is the second line —
                    // recency order is the trap.
                    let pair = threads.prefix(2).sorted { $0.started > $1.started }
                    return "TOPICS:\n" + pair.map {
                        "  \($0.term) — first searched \($0.started.formatted(.dateTime.year().month().day()))"
                    }.joined(separator: "\n")
                },
                truth: { _, threads, _ in
                    threads.prefix(2).min { $0.started < $1.started }.map(\.term) ?? ""
                }
            ),
            Case(
                id: "absent-site",
                capability: "negation",
                question: """
                    Which ONE of these is NOT in the list above: wikipedia.example, \
                    and the hosts shown? Answer with just that name.
                    """,
                evidence: { stats, _, _ in
                    let top = stats.topHosts.prefix(3)
                    guard top.count == 3 else { return "" }
                    return "HOSTS:\n" + top.map { "  \($0.host)" }.joined(separator: "\n")
                },
                truth: { _, _, _ in "wikipedia.example" }
            ),
        ]
    }

    /// Run the suite. `narrate` is the backend — a closure so Apple, Ollama, or a stub in a
    /// test all score identically.
    public static func run(
        cases: [Case] = Eval.cases(),
        stats: HistoryStats,
        threads: [IntentThread],
        leaks: [LocationLeak],
        runs: Int = 1,
        narrate: (String) async throws -> String
    ) async -> [Aggregate] {
        var aggregates: [Aggregate] = []

        for c in cases {
            let evidence = c.evidence(stats, threads, leaks)
            guard !evidence.isEmpty else { continue }
            let truth = c.truth(stats, threads, leaks)
            let prompt = """
                \(evidence)

                \(c.question)
                Use ONLY the evidence above. Never name a place, company, or product that is \
                not written in it.
                """

            var correct = 0, clean = 0, sample = ""
            var inventions: [String] = []
            var seenInvention = Set<String>()

            for _ in 0..<max(1, runs) {
                let answer = ((try? await narrate(prompt)) ?? "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if sample.isEmpty { sample = answer }

                let grounded = groundedness(answer: answer, evidence: evidence)
                if grounded.passed { clean += 1 }
                for word in grounded.invented where seenInvention.insert(word.lowercased()).inserted {
                    inventions.append(word)
                }
                // `no-geocoding` has no string to match — refusing to name a place IS the
                // correct answer, so groundedness is its whole score.
                let isCorrect = c.id == "no-geocoding"
                    ? grounded.passed
                    : !truth.isEmpty && answer.lowercased().contains(truth.lowercased())
                if isCorrect { correct += 1 }
            }

            aggregates.append(Aggregate(
                id: c.id, capability: c.capability, truth: truth, runs: max(1, runs),
                correct: correct, clean: clean, inventions: inventions, sample: sample
            ))
        }
        return aggregates
    }
}
