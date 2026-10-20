import Foundation
import Testing
import PastportKit
@testable import PastportEval

@Suite("Ask eval fixture")
struct AskEvalTests {
    private let now = Date()
    private var fixture: AskEvalFixture { AskEvalFixture(now: now) }

    @Test func fixtureHasFifteenOrMoreQuestionsWithUniqueIDs() {
        let ids = fixture.questions.map(\.id)
        #expect(ids.count >= 15)
        #expect(Set(ids).count == ids.count)
    }

    @Test func fixtureHostCountsHaveNoTiesInTheTopThree() {
        let counts = Dictionary(grouping: fixture.visits, by: \.host).mapValues(\.count)
        let top = counts.values.sorted(by: >)
        #expect(Array(top.prefix(4)) == [9, 6, 5, 4])
    }

    @Test func juneHasExactlyTwoBookingLikePagesAndParisIsTheOnlyPlace() {
        let calendar = Calendar.current
        let june = fixture.visits.filter { calendar.component(.month, from: $0.time) == 6 }
        #expect(Bookings.scan(from: june).count == 2)
        #expect(Movements.scan(from: fixture.visits).compactMap(\.place).allSatisfy { $0.localizedCaseInsensitiveContains("paris") })
    }

    @Test func theKyotoSearchesFormOneResearchThread() {
        let threads = Threads.scan(from: fixture.visits)
        #expect(threads.contains { $0.term == "kyoto" })
    }

    @Test func aCorrectAnswerPassesAndAWrongOneFails() throws {
        let q = try #require(fixture.questions.first { $0.id == "top-sites" })
        let good = AskEval.score(q, answer: "Your top sites are wiki.example (9), news.example (6) and shop.example (5).", corpus: fixture.corpus)
        #expect(good.correct)
        #expect(good.invented.isEmpty)
        let bad = AskEval.score(q, answer: "Mostly recipes.example and wiki.example.", corpus: fixture.corpus)
        #expect(!bad.correct)
    }

    @Test func inventedNamesAreCountedPerAnswer() throws {
        let q = try #require(fixture.questions.first { $0.id == "places" })
        let r = AskEval.score(q, answer: "You looked at Paris and also Tokyo.", corpus: fixture.corpus)
        #expect(!r.correct)
        #expect(r.invented.contains("Tokyo"))
    }

    @Test func absentQuestionsRequireAdmittingAbsence() throws {
        let q = try #require(fixture.questions.first { $0.id == "absent-site" })
        #expect(AskEval.score(q, answer: "No retained visit to netflix.example.", corpus: fixture.corpus).correct)
        #expect(!AskEval.score(q, answer: "Yes, you visited netflix.example twice.", corpus: fixture.corpus).correct)
    }
}
