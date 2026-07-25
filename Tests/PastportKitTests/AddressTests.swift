import XCTest
@testable import PastportKit

/// The interstitial carries a full postal address next to the coordinate. Reading it is
/// what lets a card name a place without a geocoder, a network call, or a guess — which is
/// the whole difference between this and the model that answered "the bustling city of Delhi".
final class AddressTests: XCTestCase {

    /// A real leak from this project's own history, kept verbatim because the shape of the
    /// double-encoded redirect is the thing under test.
    private let mapLink = "https://example.co.in/interstitial?r=https://maps.google.com/maps?q=12,+Rue+Lepic,+Montmartre,+18th+arrondissement,+Paris,+Ile-de-France+75018,+France&sll=48.886700123456789,2.337200987654321"

    func testReadsTheAddressOutOfTheMapLink() {
        XCTAssertEqual(
            Movements.address(in: mapLink),
            "12, Rue Lepic, Montmartre, 18th arrondissement, Paris, Ile-de-France 75018, France"
        )
    }

    func testCoarseFormDropsTheDoorstepAndTheCountry() {
        // What reaches the card: enough to recognise, not enough to visit.
        let place = Movements.coarsen(Movements.address(in: mapLink))
        XCTAssertEqual(place, "18th arrondissement, Paris")
        XCTAssertFalse(place!.contains("Rue Lepic"), "flat number must not reach the card")
        XCTAssertFalse(place!.contains("75018"), "postcode must not reach the card")
    }

    func testNoAddressWhenTheLinkOnlyCarriesCoordinates() {
        // A coordinate is not an address — falling back to floats is correct here.
        XCTAssertNil(Movements.address(in: "https://maps.google.com/?q=48.88670,2.33720"))
        XCTAssertNil(Movements.address(in: "https://example.com/page"))
    }

    func testHandlesOtherMapQueryKeys() {
        XCTAssertEqual(Movements.address(in: "https://m.test/?daddr=Jalan+Pantai,+Arashiyama,+Honshu"),
                       "Jalan Pantai, Arashiyama, Honshu")
    }

    func testCoarsenIsSafeOnShortOrMissingInput() {
        XCTAssertEqual(Movements.coarsen("Arashiyama, Honshu"), "Arashiyama, Honshu")
        XCTAssertNil(Movements.coarsen(nil))
    }
}
