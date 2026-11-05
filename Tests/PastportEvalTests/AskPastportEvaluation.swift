import Evaluations
import Foundation
import FoundationModels
import Testing
import PastportKit
@testable import PastportEval

/// What Ask said to one question, and which part of the app said it.
/// The same type is the expected value (only `id` is set) and the actual value, because
/// the Evaluations protocol requires `Sample.ExpectedValue == Subject.Value`.
struct AskOutcome: Codable, Sendable {
    /// The `AskEvalQuestion.id` whose Swift-computed truth this answer is scored against.
    var id: String
    /// Everything Ask showed: model narrative plus its source lines, or the code answer.
    var answer = ""
    /// The model's own sentences, without the "Source evidence:" lines code appends.
    var narrative = ""
    /// "code" (HistoryFacts answered with no model), "model" (a narrative passed validation)
    /// or "fallback" (the deterministic evidence answer: a model error or timeout, every sentence
    /// rejected by validation, or a question whose words matched no visit, which discards the narrative).
    var path = ""
    /// Output tokens the model spent this turn; nil means it never answered (error or timeout),
    /// so a "fallback" with tokens means the model answered and code discarded it.
    var modelOutputTokens: Int?

    static func scored(as id: String) -> AskOutcome { AskOutcome(id: id) }
}

/// Measures Ask Pastport over a fixed fictional history instead of one question at a time.
/// The truth for every question is computed in Swift by `AskEvalFixture`, so the model is only
/// ever judged against facts code worked out (the umpire), never against another model.
struct AskPastportEvaluation: Evaluation {
    static let fixture = AskEvalFixture()

    /// Open questions `HistoryFacts` does not answer, so they reach the on-device model.
    /// The fixture's own questions are almost all answered in code, which is right, but measures no model.
    static let openQuestions: [AskEvalQuestion] = [
        AskEvalQuestion(id: "open-kyoto-plans", question: "What was I planning around Kyoto?",
                        truth: "searches for kyoto temples, a train pass and hotels; nothing booked",
                        mustContain: [["kyoto"]], mustNotContain: ["tokyo", "you booked", "you stayed", "you visited kyoto"]),
        AskEvalQuestion(id: "open-travel", question: "Tell me about my travel.",
                        truth: "two travel page signals in June (Seaside Hotel confirmation, an itinerary); completion not proven",
                        mustContain: [["seaside", "itinerary", "june", "jun "]], mustNotContain: ["you stayed", "you flew", "your trip was", "kyoto hotel booked"]),
        AskEvalQuestion(id: "open-privacy", question: "Is my location exposed anywhere in my history?",
                        truth: "one map link with coordinates for Paris, via an airbnb.example redirect",
                        mustContain: [["paris", "48.85", "coordinate", "location-bearing"]], mustNotContain: ["delhi", "london", "you live in", "you were in paris"]),
        AskEvalQuestion(id: "open-overview", question: "Give me an overview of my browsing.",
                        truth: "30 visits; wiki.example, news.example and shop.example lead",
                        mustContain: [["wiki.example"]], mustNotContain: ["youtube", "netflix", "hours"]),
        AskEvalQuestion(id: "open-shopping", question: "What was I shopping for?",
                        truth: "kettle listings on shop.example",
                        mustContain: [["kettle", "shop.example"]], mustNotContain: ["you bought", "you purchased", "toaster"]),
        AskEvalQuestion(id: "open-cooking", question: "What have I been cooking lately?",
                        truth: "only that soup recipe pages were opened; not what was cooked",
                        mustContain: [["soup", "recipe"]], mustNotContain: ["you cooked", "you made", "pasta", "curry"]),
    ]
    static let allQuestions: [AskEvalQuestion] = fixture.questions + openQuestions
    /// The fixture's corpus plus fixed wording the app itself puts in front of the model or the
    /// person (the no-match answer, and the "Other" category every .example host falls into),
    /// so app-written words are not scored as model inventions.
    static let corpus = fixture.corpus + "\nNo retained page title or URL matched in this history window. categories: Other"

    static let samples: [ModelSample<AskOutcome>] = allQuestions.map { question -> ModelSample<AskOutcome> in
        ModelSample(prompt: question.question, expected: AskOutcome.scored(as: question.id))
    }
    let dataset = ArrayLoader(samples: Self.samples)

    let correct = Metric("Correct")
    let grounded = Metric("Grounded")
    let notFallback = Metric("NotFallback")
    let shortNarrative = Metric("ShortNarrative")

    /// The call the Ask field makes (a fresh conversation per question, as the first question
    /// of a session), so the code-first fact path, validation and fallbacks are all measured.
    func subject(from sample: ModelSample<AskOutcome>) async throws -> ModelSubject<AskOutcome> {
        let id = sample.expected?.id ?? ""
        let journey = HistoryJourney(visits: Self.fixture.visits, scope: "fictional evaluation history")
        let reply = try await journey.answer(sample.promptDescription)
        await journey.clear()
        let narrative = reply.text.components(separatedBy: "\nSource evidence:").first ?? reply.text
        let path = reply.receipt.mode.hasPrefix("direct") ? "code"
            : reply.text.contains("\nSource evidence:") ? "model" : "fallback"
        return ModelSubject(value: AskOutcome(id: id, answer: reply.text, narrative: narrative, path: path,
                                                       modelOutputTokens: reply.receipt.outputTokens),
                            transcript: nil)
    }

    var evaluators: Evaluators {
        Evaluator { sample, subject in
            guard let question = Self.question(sample.expected?.id) else { return correct.ignore() }
            let result = AskEval.score(question, answer: subject.value.answer, corpus: Self.corpus)
            return result.correct ? correct.passing()
                : correct.failing(rationale: "Expected \(question.truth)")
        }
        Evaluator { _, subject in
            let invented = Eval.groundedness(answer: subject.value.narrative, evidence: Self.corpus).invented
            return invented.isEmpty ? grounded.passing()
                : grounded.failing(rationale: "Invented \(invented.joined(separator: ", "))")
        }
        Evaluator { _, subject in
            subject.value.path == "fallback"
                ? notFallback.failing(rationale: "Deterministic fallback answered")
                : notFallback.passing()
        }
        Evaluator { _, subject in
            guard subject.value.path == "model" else { return shortNarrative.ignore() }
            let words = subject.value.narrative.split(whereSeparator: \.isWhitespace).count
            return words <= 80 ? shortNarrative.passing() : shortNarrative.failing(rationale: "\(words) words")
        }
    }

    func aggregateMetrics(using aggregator: inout MetricsAggregator) {
        aggregator.group("Answer") { group in
            group.computeMean(of: correct)
            group.computeMean(of: grounded)
        }
        aggregator.group("Path") { group in
            group.computeMean(of: notFallback)
            group.computeMean(of: shortNarrative)
        }
    }

    static func question(_ id: String?) -> AskEvalQuestion? {
        allQuestions.first { $0.id == id }
    }
}

/// Runs only where Apple Intelligence is on. `swift test` on a Mac with Apple Intelligence
/// runs it for real; open Xcode's Report navigator › Evaluations for every row.
@Suite struct AskPastportEvaluationTests {
    static let evaluation = AskPastportEvaluation()

    @Test(.enabled(if: SystemLanguageModel.default.isAvailable, "Needs Apple Intelligence"),
          .evaluates(Self.evaluation))
    func askAnswersFromTheRetainedHistory() async throws {
        let result = EvaluationContext.current.result
        print("EVAL: Ask Pastport\n\(result.groupedSummary)")
        let asked = result.detailed[Self.evaluation.inputColumn]
        let said = result.detailed[Self.evaluation.responseColumn]
        let correct = result.detailed[metric: Self.evaluation.correct]
        let grounded = result.detailed[metric: Self.evaluation.grounded]
        for row in 0..<said.count {
            let outcome = said[row]?.value
            let flat = (outcome?.answer ?? "").replacingOccurrences(of: "\n", with: " ")
            let marks = [correct[row]?.value == .failing ? "WRONG" : nil,
                         grounded[row]?.value == .failing ? "INVENTED" : nil].compactMap { $0 }
            let tokens = outcome?.path == "fallback" ? (outcome?.modelOutputTokens.map { " model-discarded:\($0)tok" } ?? " model-no-answer") : ""
            print("EVAL row [\(outcome?.path ?? "?")\(tokens)] \(marks.joined(separator: ","))"
                  + " Q: \(asked[row]?.promptDescription ?? "?") → \(flat.prefix(240))")
            if let q = AskPastportEvaluation.question(outcome?.id), !marks.isEmpty {
                print("   expected: \(q.truth)")
                let invented = Eval.groundedness(answer: outcome?.narrative ?? "", evidence: AskPastportEvaluation.corpus).invented
                if !invented.isEmpty { print("   invented: \(invented.joined(separator: ", "))") }
            }
        }
        #expect(result.aggregateValue(.mean(of: Self.evaluation.correct)) >= 0.75)
        #expect(result.aggregateValue(.mean(of: Self.evaluation.grounded)) >= 0.85,
                "a narrative should name only sites, places and figures in the history")
        #expect(result.aggregateValue(.mean(of: Self.evaluation.notFallback)) >= 0.7,
                "most answers should come from code or a validated model narrative, not the fallback")
    }
}
