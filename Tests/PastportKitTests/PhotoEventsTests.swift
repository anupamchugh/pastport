import XCTest
@testable import PastportKit

final class PhotoEventsTests: XCTestCase {
    private let day: TimeInterval = 24 * 3600
    private let base = Date(timeIntervalSince1970: 1_750_000_000)

    private func photo(at offset: TimeInterval, screenshot: Bool = false,
                       labels: [String] = []) -> PhotoRecord {
        PhotoRecord(time: base.addingTimeInterval(offset),
                    isScreenshot: screenshot, labels: labels)
    }

    func testEmptyInputYieldsNoEvents() {
        XCTAssertTrue(PhotoEvents.cluster([]).isEmpty)
    }

    func testSinglePhotoMakesOneEvent() {
        let events = PhotoEvents.cluster([photo(at: 0)])
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events[0].photoCount, 1)
        XCTAssertEqual(events[0].screenshotCount, 0)
        XCTAssertEqual(events[0].start, base)
        XCTAssertEqual(events[0].end, base)
    }

    func testSplitsOnGapLargerThan36Hours() {
        let events = PhotoEvents.cluster([
            photo(at: 0), photo(at: day),          // burst one
            photo(at: day + 37 * 3600),            // 37h later — new event
        ])
        XCTAssertEqual(events.count, 2)
        XCTAssertEqual(events[0].photoCount, 2)
        XCTAssertEqual(events[1].photoCount, 1)
    }

    func testKeepsBurstTogetherWithinGap() {
        let events = PhotoEvents.cluster([
            photo(at: 0), photo(at: day), photo(at: 2 * day),
        ])
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events[0].start, base)
        XCTAssertEqual(events[0].end, base.addingTimeInterval(2 * day))
    }

    func testCountsScreenshotsSeparatelyFromPhotos() {
        let events = PhotoEvents.cluster([
            photo(at: 0), photo(at: 3600, screenshot: true),
            photo(at: 7200, screenshot: true),
        ])
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events[0].photoCount, 1)
        XCTAssertEqual(events[0].screenshotCount, 2)
    }

    func testAggregatesLabelsMostFrequentFirst() {
        let events = PhotoEvents.cluster([
            photo(at: 0, labels: ["outdoor", "palm_tree"]),
            photo(at: 3600, labels: ["outdoor", "sky"]),
            photo(at: 7200, labels: ["outdoor"]),
        ])
        XCTAssertEqual(events[0].labels.first, "outdoor")
        XCTAssertEqual(Set(events[0].labels), ["outdoor", "palm_tree", "sky"])
    }

    func testUnsortedInputClustersTheSame() {
        let sorted = PhotoEvents.cluster([photo(at: 0), photo(at: 3600)])
        let shuffled = PhotoEvents.cluster([photo(at: 3600), photo(at: 0)])
        XCTAssertEqual(sorted.count, shuffled.count)
        XCTAssertEqual(sorted[0].start, shuffled[0].start)
        XCTAssertEqual(sorted[0].photoCount, shuffled[0].photoCount)
    }

    func testCustomGapIsRespected() {
        let events = PhotoEvents.cluster([photo(at: 0), photo(at: 2 * 3600)],
                                         gap: 3600)
        XCTAssertEqual(events.count, 2)
    }

    func testStatusLineDisclosesTheCapAndLimitedAccess() {
        let records = [photo(at: 0)]
        let capped = PhotoRead(records: (0..<500).map { photo(at: TimeInterval($0)) }, totalInWindow: 501, isLimitedAccess: false)
        XCTAssertTrue(PhotoEvents.statusLine(for: capped).contains("Showing the newest 500 of 501"))
        let full = PhotoRead(records: records, totalInWindow: 1, isLimitedAccess: false)
        XCTAssertFalse(PhotoEvents.statusLine(for: full).contains("Showing the newest"))
        let limited = PhotoRead(records: records, totalInWindow: 1, isLimitedAccess: true)
        XCTAssertTrue(PhotoEvents.statusLine(for: limited).contains("Counting only the photos you shared with Pastport"))
    }
}
