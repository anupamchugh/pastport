import XCTest
@testable import PastportKit

final class EvalTests: XCTestCase {

    // MARK: - the regression this whole file exists for

    /// The actual failure: `brief` was given the coordinate 48.88670,2.33720 and wrote
    /// "the bustling city of Delhi". It was not Delhi. Nothing in the package can geocode.
    func testCatchesTheDelhiHallucination() {
        let evidence = "  a coordinate was recorded: 48.88670,2.33720"
        let answer = "Last month you visited the bustling city of Delhi."
        let result = Eval.groundedness(answer: answer, evidence: evidence)

        XCTAssertFalse(result.passed)
        XCTAssertTrue(result.invented.contains("Delhi"))
    }

    func testAcceptsAnAnswerThatRefusesToGuess() {
        let evidence = "  a coordinate was recorded: 48.88670,2.33720"
        let answer = "A coordinate was recorded, but the evidence names no place."
        XCTAssertTrue(Eval.groundedness(answer: answer, evidence: evidence).passed)
    }

    // MARK: - groundedness mechanics

    func testNamesPresentInEvidenceAreGrounded() {
        let evidence = "  searched: kyoto visa\n  visited: tripadvisor.com"
        let answer = "You were checking visa rules, and landed on Tripadvisor."
        let result = Eval.groundedness(answer: answer, evidence: evidence)
        XCTAssertTrue(result.passed, "invented: \(result.invented)")
        XCTAssertGreaterThan(result.claimsChecked, 0)
    }

    func testInventedFiguresAreCaught() {
        let evidence = "TOP SITES:\n  youtube.com — 11018 visits"
        let answer = "You visited youtube.com around 40000 times."
        XCTAssertTrue(Eval.groundedness(answer: answer, evidence: evidence).invented.contains("40000"))
    }

    func testSentenceOpenersAndCalendarWordsAreNotClaims() {
        // "You", "Your", "Monday" and friends are voice, not assertions — flagging them
        // would drown the real signal.
        let result = Eval.groundedness(
            answer: "You were busy. Your Monday looked different. Overall, this was inferring.",
            evidence: "nothing here"
        )
        XCTAssertTrue(result.passed, "invented: \(result.invented)")
    }

    func testAnEmptyAnswerInventsNothingButChecksNothing() {
        let result = Eval.groundedness(answer: "", evidence: "youtube.com")
        XCTAssertTrue(result.passed)
        XCTAssertEqual(result.claimsChecked, 0, "a vacuous pass must be distinguishable")
    }

    func testDuplicateInventionsAreReportedOnce() {
        let result = Eval.groundedness(answer: "Delhi. Again, Delhi.", evidence: "nothing")
        XCTAssertEqual(result.invented.count, 1)
    }

    // MARK: - scoring a whole run

    func testFactualCaseScoresAgainstComputedTruth() async {
        let stats = HistoryStats(
            total: 100,
            categories: [],
            hours: (0..<24).map { HourStat(hour: $0, visits: $0 == 19 ? 90 : 1) },
            topHosts: [HostStat(host: "youtube.com", visits: 90),
                       HostStat(host: "github.com", visits: 10)]
        )

        // A perfect backend: echoes exactly what the evidence supports.
        let honest = await Eval.run(
            cases: Eval.cases().filter { $0.id == "top-site" || $0.id == "peak-hour" },
            stats: stats, threads: [], leaks: [],
            narrate: { prompt in prompt.contains("HOUR") ? "19" : "youtube.com" }
        )
        XCTAssertEqual(honest.count, 2)
        XCTAssertTrue(honest.allSatisfy { $0.correct == $0.runs },
                      "an honest backend should score every run")

        // A confident, wrong one.
        let wrong = await Eval.run(
            cases: Eval.cases().filter { $0.id == "top-site" },
            stats: stats, threads: [], leaks: [],
            narrate: { _ in "The person mostly used Reddit." }
        )
        XCTAssertEqual(wrong[0].correct, 0)
        XCTAssertTrue(wrong[0].inventions.contains("Reddit"))
    }

    /// A model that is right half the time must not read as a clean pass — this is the
    /// whole reason for sampling rather than trusting one run.
    func testFlakinessIsSurfacedNotAveragedAway() async {
        let stats = HistoryStats(
            total: 10, categories: [],
            hours: (0..<24).map { HourStat(hour: $0, visits: $0 == 19 ? 9 : 0) },
            topHosts: [HostStat(host: "youtube.com", visits: 9)]
        )
        var call = 0
        let flaky = await Eval.run(
            cases: Eval.cases().filter { $0.id == "top-site" },
            stats: stats, threads: [], leaks: [], runs: 4,
            narrate: { _ in
                call += 1
                return call.isMultiple(of: 2) ? "youtube.com" : "github.com"
            }
        )
        XCTAssertEqual(flaky[0].runs, 4)
        XCTAssertEqual(flaky[0].correct, 2)
        XCTAssertTrue(flaky[0].unstable, "a 2/4 case must be reported as unstable")
    }

    func testCasesWithNoEvidenceAreSkippedNotFailed() async {
        // An empty window must not be scored as the model getting things wrong.
        let empty = HistoryStats(total: 0, categories: [], hours: [], topHosts: [])
        let results = await Eval.run(stats: empty, threads: [], leaks: [],
                                     narrate: { _ in "anything" })
        XCTAssertTrue(results.isEmpty)
    }
}
