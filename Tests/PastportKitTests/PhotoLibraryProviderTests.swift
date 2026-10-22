import Foundation
import XCTest
@testable import PastportKit

final class PhotoLibraryProviderTests: XCTestCase {
    private final class State: @unchecked Sendable {
        var calls = 0
    }

    private final class TaskBox: @unchecked Sendable {
        var task: Task<[PhotoRecord], Error>?
    }

    func testProviderMapsSyntheticMetadataAtPhotoRecordBoundary() async throws {
        let metadata = [
            PhotoAssetMetadata(time: Date(timeIntervalSince1970: 100), isScreenshot: true,
                               imageData: Data("private screenshot".utf8)),
            PhotoAssetMetadata(time: Date(timeIntervalSince1970: 200), isScreenshot: false,
                               imageData: Data("synthetic photo".utf8))
        ]
        let provider = PhotoLibraryProvider(
            metadata: { _, _ in metadata },
            classify: { data in
                XCTAssertEqual(data, Data("synthetic photo".utf8))
                return [PhotoLabel(identifier: "beach", confidence: 0.9),
                        PhotoLabel(identifier: "person", confidence: 0.8)]
            }
        )

        let result = try await provider.records(since: .distantPast, limit: 10)

        XCTAssertEqual(result.map(\.isScreenshot), [true, false])
        XCTAssertEqual(result.map(\.labels), [[], ["beach", "person"]])
        XCTAssertEqual(PhotoEvents.cluster(result).first?.screenshotCount, 1)
    }

    func testProviderDistinguishesEmptyAndInvalidBounds() async throws {
        let empty = PhotoLibraryProvider(metadata: { _, _ in [] }, classify: { _ in [] })
        do {
            _ = try await empty.records(since: .distantPast, limit: 10)
            XCTFail("empty library must be distinguishable")
        } catch PhotoLibraryError.empty {
            // expected
        }

        let provider = PhotoLibraryProvider(metadata: { _, _ in [
            PhotoAssetMetadata(time: Date(), isScreenshot: false, imageData: nil)
        ] }, classify: { _ in [] })
        do {
            _ = try await provider.records(since: .distantPast, limit: 0)
            XCTFail("invalid bound must not fetch")
        } catch PhotoLibraryError.invalidLimit {
            // expected
        }

        let state = State()
        let bounded = PhotoLibraryProvider(metadata: { _, _ in
            state.calls += 1
            return []
        }, classify: { _ in [] })
        do {
            _ = try await bounded.records(since: .distantPast, limit: 501)
            XCTFail("hard provider bound must reject before source access")
        } catch PhotoLibraryError.invalidLimit {
            XCTAssertEqual(state.calls, 0)
        }
    }

    func testPublicRecordsDropsResultCancelledAfterSourceReturns() async throws {
        let box = TaskBox()
        let provider = PhotoLibraryProvider(metadata: { _, _ in
            box.task?.cancel()
            return [PhotoAssetMetadata(time: Date(), isScreenshot: true, imageData: nil)]
        }, classify: { _ in [] })
        box.task = Task { try await provider.records(since: .distantPast, limit: 1) }

        do {
            _ = try await box.task!.value
            XCTFail("cancellation after source completion must not publish records")
        } catch is CancellationError {
            // expected
        }
    }

    func testSyntheticLastAssetReturnsNormally() async throws {
        let provider = PhotoLibraryProvider(metadata: { _, _ in [
            PhotoAssetMetadata(time: Date(), isScreenshot: false, imageData: Data([1]))
        ] }, classify: { _ in [PhotoLabel(identifier: "beach", confidence: 0.9)] })

        let result = try await provider.records(since: .distantPast, limit: 1)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].labels, ["beach"])
    }

    func testLabelsFilterConfidenceAndCap() async throws {
        let provider = PhotoLibraryProvider(metadata: { _, _ in [
            PhotoAssetMetadata(time: Date(), isScreenshot: false, imageData: Data([1]))
        ] }, classify: { _ in
            [PhotoLabel(identifier: "low", confidence: 0.49),
             PhotoLabel(identifier: "third", confidence: 0.7),
             PhotoLabel(identifier: "first", confidence: 0.99),
             PhotoLabel(identifier: "fifth", confidence: 0.5),
             PhotoLabel(identifier: "second", confidence: 0.8),
             PhotoLabel(identifier: "sixth", confidence: 0.4),
             PhotoLabel(identifier: "fourth", confidence: 0.6)]
        })

        let result = try await provider.records(since: .distantPast, limit: 1)

        XCTAssertEqual(result[0].labels, ["first", "second", "third", "fourth", "fifth"])
    }

    func testCancellationFromLastLabelDoesNotBecomeACompletedRecord() async throws {
        let state = State()
        let provider = PhotoLibraryProvider(metadata: { _, _ in [
            PhotoAssetMetadata(time: Date(), isScreenshot: false, imageData: Data([1])),
            PhotoAssetMetadata(time: Date(), isScreenshot: false, imageData: Data([2]))
        ] }, classify: { _ in
            state.calls += 1
            if state.calls == 2 { throw CancellationError() }
            return [PhotoLabel(identifier: "first", confidence: 0.9)]
        })

        do {
            _ = try await provider.records(since: .distantPast, limit: 2)
            XCTFail("cancellation must escape the mapping boundary")
        } catch is CancellationError {
            XCTAssertEqual(state.calls, 2)
        }
    }


    // MARK: Newest first, cap disclosure, limited access (slice 2)

    private func assets(count: Int) -> [PhotoAssetMetadata] {
        (0..<count).map {
            PhotoAssetMetadata(time: Date(timeIntervalSince1970: Double($0)), isScreenshot: false, imageData: nil)
        }
    }

    func testNewestKeepsTheNewestRecordsAndDropsTheOldest() {
        let kept = PhotoLibraryProvider.newest(assets(count: 501), limit: 500)
        XCTAssertEqual(kept.count, 500)
        XCTAssertEqual(kept.first?.time, Date(timeIntervalSince1970: 1))
        XCTAssertEqual(kept.last?.time, Date(timeIntervalSince1970: 500))
        XCTAssertFalse(kept.contains { $0.time == Date(timeIntervalSince1970: 0) })
    }

    func testReadReportsTotalAndClassifiesOnlyKeptPhotos() async throws {
        let state = State()
        let provider = PhotoLibraryProvider(
            metadata: { _, _ in (0..<501).map {
                PhotoAssetMetadata(time: Date(timeIntervalSince1970: Double($0)), isScreenshot: false,
                                   imageData: Data("x".utf8))
            } },
            classify: { _ in state.calls += 1; return [] }
        )
        let result = try await provider.read(since: .distantPast, limit: 500)
        XCTAssertEqual(result.records.count, 500)
        XCTAssertEqual(result.totalInWindow, 501)
        XCTAssertTrue(result.isTruncated)
        XCTAssertEqual(state.calls, 500, "the dropped photo's pixels must never be opened")
    }

    func testReadAtTheCapIsNotTruncated() async throws {
        let provider = PhotoLibraryProvider(metadata: { _, _ in self.assets(count: 500) }, classify: { _ in [] })
        let result = try await provider.read(since: .distantPast, limit: 500)
        XCTAssertEqual(result.totalInWindow, 500)
        XCTAssertFalse(result.isTruncated)
    }

    func testReadCarriesTheLimitedAccessFlag() async throws {
        let limited = PhotoLibraryProvider(metadata: { _, _ in self.assets(count: 1) }, classify: { _ in [] },
                                           isLimitedAccess: true)
        let full = PhotoLibraryProvider(metadata: { _, _ in self.assets(count: 1) }, classify: { _ in [] })
        let limitedRead = try await limited.read(since: .distantPast, limit: 500)
        let fullRead = try await full.read(since: .distantPast, limit: 500)
        XCTAssertTrue(limitedRead.isLimitedAccess)
        XCTAssertFalse(fullRead.isLimitedAccess)
    }

}
