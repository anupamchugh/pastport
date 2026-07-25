import XCTest
@testable import PastportKit

final class DemoDataTests: XCTestCase {
    func testDemoRowsAreNonEmptyAndUseReservedExampleHosts() {
        XCTAssertFalse(DemoData.visits.isEmpty)
        XCTAssertTrue(DemoData.visits.allSatisfy { $0.host.hasSuffix(".example") })
        XCTAssertFalse(DemoData.visits.contains { $0.url.localizedCaseInsensitiveContains("bengaluru") })
    }

    func testDemoRowsExerciseMovementAndTravelCards() {
        let movement = Movements.scan(from: DemoData.visits)
        XCTAssertEqual(movement.first?.fromApp, "Airbnb")
        XCTAssertFalse(Bookings.scan(from: DemoData.visits).filter(\.isTravel).isEmpty)
    }
}
