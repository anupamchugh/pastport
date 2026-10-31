import Foundation
import XCTest
@testable import PastportKit

final class TimelineExportTests: XCTestCase {

    func testExportBookingToCalendarICS() {
        let booking = Booking(
            time: Date(timeIntervalSince1970: 1770000000), // fixed timestamp
            host: "jal.co.jp",
            kind: .ticket,
            title: "JAL Flight JL123: Haneda to Itami",
            url: "https://jal.co.jp/booking/eticket/JL123"
        )

        let ics = TimelineExport.toICalendar(booking: booking)

        XCTAssertTrue(ics.contains("BEGIN:VCALENDAR"))
        XCTAssertTrue(ics.contains("BEGIN:VEVENT"))
        XCTAssertTrue(ics.contains("SUMMARY:JAL Flight JL123: Haneda to Itami"))
        XCTAssertTrue(ics.contains("URL:https://jal.co.jp/booking/eticket/JL123"))
        XCTAssertTrue(ics.contains("END:VEVENT"))
        XCTAssertTrue(ics.contains("END:VCALENDAR"))
    }

    func testExportIntentTaskToReminderItem() {
        let task = IntentTask(
            id: UUID(),
            title: "Reserve accommodation in Kyoto",
            reason: "Flight to Osaka is booked but no hotel was detected in history",
            isMissingGap: true,
            actionURL: "https://booking.com/search?ss=Kyoto"
        )

        let reminder = TimelineExport.toReminderItem(task: task, dueDate: Date().addingTimeInterval(86400))

        XCTAssertEqual(reminder.title, "Reserve accommodation in Kyoto")
        XCTAssertTrue(reminder.notes.contains("Flight to Osaka is booked"))
        XCTAssertEqual(reminder.url, "https://booking.com/search?ss=Kyoto")
        XCTAssertNotNil(reminder.dueDate)
    }
}
