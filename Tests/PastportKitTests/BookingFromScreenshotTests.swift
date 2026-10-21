import Foundation
import Testing
@testable import PastportKit

@Suite("Booking from screenshot")
struct BookingFromScreenshotTests {
    private func day(of date: Date) -> DateComponents {
        Calendar.current.dateComponents([.year, .month, .day], from: date)
    }

    @Test func datedFerryETicketBecomesATicketBooking() throws {
        let evidence = ScreenshotScrubber.scrub(["Island Ferries", "E-ticket", "Departs 14 Jun 2026", "Seat 12A"])
        let booking = try #require(BookingFromScreenshot.detect(evidence))
        #expect(booking.kind == .ticket)
        #expect(day(of: booking.date) == DateComponents(year: 2026, month: 6, day: 14))
        #expect(booking.title == "Island Ferries")
    }

    @Test func aTicketThatAlsoSaysAmountPaidIsStillABooking() throws {
        let evidence = ScreenshotScrubber.scrub(["Island Ferries", "E-ticket", "Departs 14 Jun 2026", "Amount paid 1,200"])
        #expect(evidence.kind != .banking)
        let booking = try #require(BookingFromScreenshot.detect(evidence))
        #expect(booking.kind == .ticket)
    }

    @Test func aBankScreenWithAmountPaidStaysBankingWithNoBooking() {
        let evidence = ScreenshotScrubber.scrub(["Account balance 4,000", "E-ticket", "14 Jun 2026", "Amount paid 1,200"])
        #expect(evidence.kind == .banking)
        #expect(BookingFromScreenshot.detect(evidence) == nil)
    }

    @Test func aChatScreenshotMakesNoBooking() {
        let evidence = ScreenshotScrubber.scrub(["WhatsApp", "Here is my e-ticket for 14 Jun 2026"])
        #expect(evidence.kind == .chat)
        #expect(BookingFromScreenshot.detect(evidence) == nil)
    }

    @Test func aReceiptWithoutATicketMarkerStaysAReceipt() {
        let evidence = ScreenshotScrubber.scrub(["Corner Shop", "Confirmation number 88421", "14 Jun 2026"])
        #expect(evidence.kind == .receipt)
        #expect(BookingFromScreenshot.detect(evidence) == nil)
    }

    @Test func bookingKindIsTheSharedBookingKind() throws {
        let evidence = ScreenshotScrubber.scrub(["Demo Stay, Paris", "Check-in 1 Jul 2026"])
        let booking = try #require(BookingFromScreenshot.detect(evidence))
        let kind: Booking.Kind = booking.kind
        #expect(kind == .confirmation)
    }
}
