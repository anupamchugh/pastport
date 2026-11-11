import Testing
@testable import PastportKit

@Suite("Skeptic checks")
struct SkepticChecksTests {
    private let evidence = ["Total visits: 12. Top sites: guide.example: 5, news.example: 3.", "booking-like pages: 2"]

    private func review(_ answer: String) -> [SkepticFinding] {
        SkepticChecks.review(answer: answer, evidenceLines: evidence)
    }

    @Test("an answer whose numbers are all in the evidence has nothing to challenge")
    func cleanAnswerHolds() {
        #expect(review("You opened 12 pages, 5 of them on guide.example.").isEmpty)
        #expect(review("I don't know. No matching history was found.").isEmpty)
    }

    @Test("a number the evidence does not contain is quoted, once")
    func unsupportedNumberIsQuoted() {
        let findings = review("You opened 12 pages and 7 on Monday. Again, 7 on Monday.")
        #expect(findings.map(\.issue) == [.unsupportedNumber])
        #expect(findings.first?.quote == "7")
    }

    @Test("thousands separators and decimals compare as written in the evidence")
    func numberFormats() {
        let findings = SkepticChecks.review(answer: "About 1,200 visits and 4.5 per day.", evidenceLines: ["1200 visits, 4.5 per day"])
        #expect(findings.isEmpty)
    }

    @Test("a completed purchase, booking or trip claim is quoted as the answer wrote it")
    func completedActionClaim() {
        let findings = review("Your hotel was booked and you travelled to Kyoto.")
        #expect(findings.contains { $0.issue == .completedActionClaim && $0.quote == "was booked" })
        #expect(findings.contains { $0.issue == .completedActionClaim && $0.quote == "you travelled" })
    }

    @Test("'confirmed' is a claim unless the answer says it does not confirm")
    func confirmedNegation() {
        #expect(review("The page confirmed the stay.").contains { $0.quote.lowercased() == "confirmed" })
        #expect(review("This page does not confirm a booking.").isEmpty)
    }

    @Test("reading, watching and time-spent claims are challenged: a visit is not proof")
    func timeAndIntentClaims() {
        let findings = review("You read the guide and you spent a lot of time there.")
        #expect(findings.filter { $0.issue == .timeOrIntentClaim }.map(\.quote) == ["You read", "you spent"])
    }

    @Test("a model's finding is kept only when its quote is in the answer, and shows the answer's own words")
    func modelFindingsMustQuoteTheAnswer() {
        let answer = "Most of your visits were about Kyoto. You obviously love travel."
        let accepted = SkepticChecks.accept(
            model: [
                .init(quote: "you obviously LOVE travel", issue: .overreach, why: "Guessing a feeling\nfrom page visits."),
                .init(quote: "You booked Tokyo", issue: .overreach, why: "Not in the answer."),
                .init(quote: "", issue: .unclear, why: "Empty quote."),
            ],
            answer: answer, existing: [])
        #expect(accepted.count == 1)
        #expect(accepted[0].quote == "You obviously love travel", "the quote is the answer's text, not the model's spelling")
        #expect(accepted[0].issue == .overreach)
        #expect(!accepted[0].why.contains("\n"))
    }

    @Test("model findings cannot repeat a code finding, and at most three findings show in all")
    func acceptIsBounded() {
        let answer = "a b c d e f"
        let existing = [SkepticFinding(issue: .unsupportedNumber, quote: "a", why: "x")]
        let accepted = SkepticChecks.accept(
            model: ["a", "b", "c", "d", "e"].map { .init(quote: $0, issue: .unclear, why: "Unclear.") },
            answer: answer, existing: existing)
        #expect(accepted.map(\.quote) == ["b", "c"], "'a' is already a finding; the total stays at three")
    }

    @Test("a model reason is trimmed to a short single line")
    func reasonIsBounded() {
        let accepted = SkepticChecks.accept(
            model: [.init(quote: "b", issue: .unclear, why: String(repeating: "long ", count: 80))],
            answer: "a b", existing: [])
        #expect(accepted[0].why.count <= 140)
    }

    @Test("a review with no findings holds; any finding needs care; model status is reported")
    func verdicts() {
        #expect(SkepticReview(findings: [], model: .notRun).verdict == .holds)
        let careful = SkepticReview(findings: [SkepticFinding(issue: .unsupportedNumber, quote: "7", why: "x")], model: .reviewed)
        #expect(careful.verdict == .needsCare)
    }
}
