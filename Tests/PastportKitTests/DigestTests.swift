import XCTest
@testable import PastportKit

/// The eval measured both backends at 0/3 on arithmetic and 2/3 on picking a maximum from
/// 24 rows. The digest prompt used to hand them eight raw counts to rank — the one
/// operation they cannot do. Ranking happens in Swift now, and these assertions exist so
/// nobody quietly puts the numbers back.
final class DigestTests: XCTestCase {

    private let items = [("Video/Music", 44926), ("Other", 13572),
                         ("Social", 4831), ("Dev", 4488)]

    func testRankedEmitsAnOrderingNotATableOfFigures() {
        let line = Digest.ranked(items, label: "CATEGORIES")
        XCTAssertTrue(line.contains("Video/Music"), "the winner must be named")
        XCTAssertTrue(line.contains("largest"), "the ordering must be stated in words")
        // No count may reach the model. This is the whole point of the helper.
        for (_, count) in items {
            XCTAssertFalse(line.contains(String(count)), "count \(count) leaked into the prompt")
        }
    }

    func testRankedSortsRatherThanTrustingInputOrder() {
        let shuffled = [("Social", 4831), ("Video/Music", 44926), ("Dev", 4488)]
        XCTAssertTrue(Digest.ranked(shuffled, label: "X").hasPrefix("X (already ranked"))
        XCTAssertTrue(Digest.ranked(shuffled, label: "X").contains("Video/Music is the largest"))
    }

    func testRankedIsSafeWhenEmpty() {
        XCTAssertEqual(Digest.ranked([], label: "CATEGORIES"), "")
    }

    func testFullPromptCarriesNoRawCounts() {
        let prompt = Digest.prompt(
            categorySummary: Digest.ranked(items, label: "CATEGORIES"),
            topSites: Digest.ranked([("example.com", 11018)], label: "SITES"),
            movements: [], threads: ["Jun 12: kyoto, visa"], days: 90, instruction: nil
        )
        XCTAssertFalse(prompt.contains("44926"))
        XCTAssertFalse(prompt.contains("11018"))
        XCTAssertTrue(prompt.contains("kyoto"), "real evidence still reaches the model")
    }
}
