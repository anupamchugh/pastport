import XCTest
@testable import PastportKit

final class AskWorkflowTests: XCTestCase {
    private let visits = [
        Visit(time: Date(), title: "Leaving Airbnb", url: "https://airbnb.example/interstitial?r=https%3A%2F%2Fmaps.example%2F%3Fq%3D18%2BRue%2BDemo%252C%2B5th%2BArrondissement%252C%2BParis%252C%2BFrance%26ll%3D48.8566%252C2.3522"),
        Visit(time: Date(), title: "Your itinerary", url: "https://flight.example/itinerary/demo"),
    ]

    func testRoutesQuestionsToSmallestEvidenceSlice() {
        XCTAssertEqual(AskWorkflow.intent(for: "where did I go?"), .location)
        XCTAssertEqual(AskWorkflow.intent(for: "what did I book?"), .travel)
        XCTAssertEqual(AskWorkflow.intent(for: "what was I researching?"), .research)
        XCTAssertEqual(AskWorkflow.intent(for: "who tracked me?"), .trackers)
        XCTAssertEqual(AskWorkflow.intent(for: "what did I read on Google?"), .research)
    }

    func testLocationEvidenceIsCoarseAndOmitsRawURLs() {
        let evidence = AskWorkflow.evidence(for: .location, visits: visits)
        XCTAssertFalse(evidence == "No location leaks found.")
        XCTAssertFalse(evidence.contains("airbnb.example/interstitial"))
        XCTAssertFalse(evidence.contains("18 Rue Demo"))
    }
}
