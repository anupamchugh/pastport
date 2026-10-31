import Foundation
import XCTest
@testable import PastportKit

final class IntentTaskSynthesizerTests: XCTestCase {

    func testDetectsMissingAccommodationGapForTravel() {
        let synthesizer = IntentTaskSynthesizer()

        // User booked a flight to Kyoto but has no hotel
        let flightBooking = Booking(
            time: Date(),
            host: "jal.co.jp",
            kind: .ticket,
            title: "JAL E-Ticket: Tokyo Haneda to Osaka Itami (Flight JL123)",
            url: "https://jal.co.jp/booking/eticket/JL123"
        )

        let thread = IntentThread(
            term: "kyoto",
            related: ["ryokan", "shinkansen", "osaka"],
            queries: [
                "kyoto to osaka train timetable - Search",
                "kyoto best ryokan with onsen - Search",
                "jal flights to itami osaka - Search"
            ],
            started: Date().addingTimeInterval(-86400 * 2),
            destinations: ["jal.co.jp", "japan-guide.com"],
            searchCount: 5
        )

        let plan = synthesizer.synthesizePlan(thread: thread, existingBookings: [flightBooking])

        XCTAssertEqual(plan.topic, "kyoto")
        XCTAssertTrue(plan.tasks.contains { $0.isMissingGap && $0.title.localizedCaseInsensitiveContains("accommodation") || $0.title.localizedCaseInsensitiveContains("hotel") || $0.title.localizedCaseInsensitiveContains("stay") },
                      "Must flag missing accommodation gap when flight is booked but no stay is confirmed: \(plan.tasks)")
        XCTAssertTrue(plan.tasks.contains { $0.title.localizedCaseInsensitiveContains("transit") || $0.title.localizedCaseInsensitiveContains("train") || $0.title.localizedCaseInsensitiveContains("pass") },
                      "Must suggest transit task: \(plan.tasks)")
    }

    func testSynthesizesTechnicalResearchTasks() {
        let synthesizer = IntentTaskSynthesizer()

        let thread = IntentThread(
            term: "metal",
            related: ["swiftui", "shaders", "pipeline"],
            queries: [
                "swiftui metal shader colorEffect - Search",
                "metal vertex and fragment pipeline swift - Search",
                "point-free metal shaders episode - Search"
            ],
            started: Date().addingTimeInterval(-3600 * 4),
            destinations: ["developer.apple.com", "pointfree.co"],
            searchCount: 4
        )

        let plan = synthesizer.synthesizePlan(thread: thread, existingBookings: [])

        XCTAssertEqual(plan.topic, "metal")
        XCTAssertFalse(plan.tasks.isEmpty)
        XCTAssertTrue(plan.readingTopics.contains { $0.localizedCaseInsensitiveContains("metal") || $0.localizedCaseInsensitiveContains("swiftui") })
        XCTAssertTrue(plan.tasks.contains { $0.title.localizedCaseInsensitiveContains("prototype") || $0.title.localizedCaseInsensitiveContains("spike") || $0.title.localizedCaseInsensitiveContains("documentation") })
    }

    func testGroundedTaskOutputHasDeterministicIDs() {
        let synthesizer = IntentTaskSynthesizer()
        let thread = IntentThread(
            term: "tax",
            related: ["deductions", "freelance"],
            queries: ["freelance developer tax deductions 2026 - Search"],
            started: Date(),
            destinations: ["irs.gov"],
            searchCount: 3
        )

        let plan1 = synthesizer.synthesizePlan(thread: thread, existingBookings: [])
        let plan2 = synthesizer.synthesizePlan(thread: thread, existingBookings: [])

        XCTAssertEqual(plan1.tasks.count, plan2.tasks.count)
        XCTAssertEqual(plan1.tasks.map(\.title), plan2.tasks.map(\.title))
    }
}
