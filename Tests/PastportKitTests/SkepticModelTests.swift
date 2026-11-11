import Foundation
import Testing
@testable import PastportKit

private struct Unlocked: Authenticating {
    func unlock(reason: String, graceMinutes: Int) async -> UnlockResult { .unlocked }
    func relock() {}
}

private actor Gate {
    private var open = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
    func wait() async { if open { return }; await withCheckedContinuation { waiters.append($0) } }
    func release() { open = true; waiters.forEach { $0.resume() }; waiters = [] }
}

private final class Calls: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    func add() { lock.withLock { count += 1 } }
    var value: Int { lock.withLock { count } }
}

private struct ScriptedSkeptic: SkepticReviewing {
    enum Mode { case returns([SkepticModelFinding]), fails, waits(Gate, [SkepticModelFinding]) }
    struct Failure: Error {}
    let mode: Mode
    let calls = Calls()

    func review(question: String, answer: String, evidenceLines: [String]) async throws -> [SkepticModelFinding] {
        calls.add()
        switch mode {
        case .returns(let findings): return findings
        case .fails: throw Failure()
        case .waits(let gate, let findings): await gate.wait(); return findings
        }
    }
}

@MainActor
@Suite("Skeptic on the model", .timeLimit(.minutes(1)))
struct SkepticModelTests {
    private let answer = "You opened 99 pages and you spent hours on guide.example."

    private func model(_ skeptic: ScriptedSkeptic, ready: Bool, status: AskTurn.Status = .answered) -> (TimelineModel, UUID) {
        let model = TimelineModel(history: nil, authenticator: Unlocked(), appleIntelligenceReady: { ready }, skeptic: skeptic)
        let turn = AskTurn(prompt: "How many pages?", answer: answer, status: status)
        model.turns = [turn]
        return (model, turn.id)
    }

    private func waitUntil(_ condition: @MainActor () -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(5)
        while !condition() {
            guard ContinuousClock.now < deadline else { Issue.record("Timed out"); return }
            try await Task.sleep(for: .milliseconds(5))
        }
    }

    private func review(_ model: TimelineModel, _ id: UUID) -> SkepticReview? {
        if case .done(let review)? = model.skepticReviews[id] { return review }
        return nil
    }

    @Test("without Apple Intelligence the code checks still run, the model is not called, and the review says so")
    func codeOnly() async throws {
        let skeptic = ScriptedSkeptic(mode: .returns([]))
        let (model, id) = model(skeptic, ready: false)
        model.challenge(id)
        try await waitUntil { review(model, id) != nil }
        let result = try #require(review(model, id))
        #expect(result.model == .notRun && result.verdict == .needsCare)
        #expect(result.findings.map(\.quote).contains("99"))
        #expect(result.findings.map(\.quote).contains("you spent"))
        #expect(skeptic.calls.value == 0)
    }

    @Test("a model finding shows only when its quote is in the answer")
    func modelFindingsAreValidated() async throws {
        let skeptic = ScriptedSkeptic(mode: .returns([
            .init(quote: "guide.example", issue: .unclear, why: "Which pages on that site?"),
            .init(quote: "You visited Paris", issue: .overreach, why: "Invented."),
        ]))
        let (model, id) = model(skeptic, ready: true)
        model.challenge(id)
        try await waitUntil { review(model, id) != nil }
        let result = try #require(review(model, id))
        #expect(result.model == .reviewed)
        #expect(result.findings.contains { $0.issue == .unclear && $0.quote == "guide.example" })
        #expect(!result.findings.contains { $0.quote.contains("Paris") })
    }

    @Test("a failing model leaves the code findings and says the model failed")
    func modelFailureKeepsCodeFindings() async throws {
        let (model, id) = model(ScriptedSkeptic(mode: .fails), ready: true)
        model.challenge(id)
        try await waitUntil { review(model, id) != nil }
        let result = try #require(review(model, id))
        #expect(result.model == .failed)
        #expect(result.findings.map(\.quote).contains("99"))
    }

    @Test("locking while the model is still thinking leaves nothing behind")
    func lockDropsALateReview() async throws {
        let gate = Gate()
        let skeptic = ScriptedSkeptic(mode: .waits(gate, [.init(quote: "guide.example", issue: .unclear, why: "Vague.")]))
        let (model, id) = model(skeptic, ready: true)
        model.challenge(id)
        try await waitUntil { skeptic.calls.value == 1 }
        #expect(model.skepticReviews[id] == .checking)
        model.lockAndClear()
        #expect(model.skepticReviews.isEmpty)
        await gate.release()
        try await Task.sleep(for: .milliseconds(100))
        #expect(model.skepticReviews.isEmpty, "a review that finishes after the lock is dropped")
    }

    @Test("an unfinished or stopped answer is not challenged, and a second tap does not run the reviewer again")
    func onlyFinishedAnswersOnceEach() async throws {
        let skeptic = ScriptedSkeptic(mode: .returns([]))
        let (answering, answeringID) = model(skeptic, ready: true, status: .answering)
        answering.challenge(answeringID)
        #expect(answering.skepticReviews.isEmpty)

        let (model, id) = model(skeptic, ready: true)
        model.challenge(id)
        model.challenge(id)
        try await waitUntil { review(model, id) != nil }
        model.challenge(id)
        try await Task.sleep(for: .milliseconds(50))
        #expect(skeptic.calls.value == 1)
    }
}
