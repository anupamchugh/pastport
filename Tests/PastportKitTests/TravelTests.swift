import XCTest
@testable import PastportKit

/// A flight, a hotel and a guesthouse are one trip, not three unrelated purchases. This is
/// what decides which commitments belong together — from what a page IS, never from who
/// runs it, so a guesthouse nobody has heard of groups the same as a major airline.
final class TravelTests: XCTestCase {

    private func booking(_ kind: Booking.Kind, _ title: String, _ url: String = "https://x.test/p")
        -> Booking {
        Booking(time: Date(), host: "x.test", kind: kind, title: title, url: url)
    }

    func testItinerariesAreTravelByDefinition() {
        XCTAssertTrue(booking(.itinerary, "Itinerary").isTravel,
                      "a bland itinerary title is still a trip")
    }

    // Found against real history: a cinema e-ticket was being filed under travel.
    func testTicketsAreNotAutomaticallyTravel() {
        XCTAssertFalse(booking(.ticket, "PVRINOX").isTravel, "a cinema ticket is not a trip")
        XCTAssertTrue(booking(.ticket, "Boarding pass — flight AB123").isTravel)
    }

    // Found against real history: "your trip" matched a video titled "…Your Tripod Broke".
    func testWholeWordMatchingOnly() {
        XCTAssertFalse(booking(.checkout, "What If You Nuked Mars and Your Tripod Broke").isTravel)
        XCTAssertNil(Bookings.classify(title: "What If Your Tripod Broke", url: "https://v.test/w"),
                     "a video title must not read as an itinerary")
    }

    // Found against real history: the most important stay of the year was being dropped,
    // because its title carries no travel vocabulary at all.
    func testAReservationConfirmationCountsEvenWithNoTravelWords() {
        XCTAssertTrue(booking(.confirmation, "Booking Confirmed - KYTO").isTravel)
    }

    // Whole-word matching initially over-corrected: "hotels" stopped matching "hotel",
    // which dropped a real accommodation confirmation whose only signal was the host.
    func testPluralsStillMatch() {
        XCTAssertTrue(booking(.confirmation, "Wave House - Arashiyama, Japan",
                              "https://hotels.test/confirm").isTravel)
        XCTAssertTrue(booking(.checkout, "2 rooms booked").isTravel)
        // The plural allowance must not reopen the substring hole: "trip" + "o" is not
        // a plural, so "tripods" still must not match.
        XCTAssertFalse(booking(.checkout, "Camera tripods on sale").isTravel)
    }

    func testStaysAreTravelFromOrdinaryVocabulary() {
        XCTAssertTrue(booking(.confirmation, "Wave House - Arashiyama, Japan - Best Price Guarantee",
                              "https://x.test/hotel/confirm").isTravel)
        XCTAssertTrue(booking(.checkout, "Japan Arrival - Arrival Card Service").isTravel)
        XCTAssertTrue(booking(.confirmation, "Your room is confirmed").isTravel)
    }

    func testOrdinaryPurchasesAreNotTravel() {
        // The section is worthless if a software subscription lands in it.
        XCTAssertFalse(booking(.checkout, "Cursor — Subscribe").isTravel)
        XCTAssertFalse(booking(.checkout, "TunnelBear: Secure VPN Service").isTravel)
        XCTAssertFalse(booking(.checkout, "Place Your Order - Amazon Checkout").isTravel)
        XCTAssertFalse(booking(.confirmation, "Order confirmation — headphones").isTravel)
    }

    func testGroupingIsIndependentOfWhoRunsTheSite() {
        // Same page shape, unknown host — must classify identically.
        let known = Booking(time: Date(), host: "bigairline.test", kind: .itinerary,
                            title: "Itinerary", url: "https://bigairline.test/itinerary")
        let obscure = Booking(time: Date(), host: "someones-guesthouse.xyz", kind: .itinerary,
                              title: "Itinerary", url: "https://someones-guesthouse.xyz/itinerary")
        XCTAssertEqual(known.isTravel, obscure.isTravel)
        XCTAssertTrue(obscure.isTravel)
    }
}
