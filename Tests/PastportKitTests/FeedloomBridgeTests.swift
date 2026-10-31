import Foundation
import XCTest
@testable import PastportKit

final class FeedloomBridgeTests: XCTestCase {
    private var tempDir: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("FeedloomBridgeTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let tempDir = tempDir {
            try? FileManager.default.removeItem(at: tempDir)
        }
        try super.tearDownWithError()
    }

    func testFindReadingSuggestionsFindsMatchingBookmarks() throws {
        let bridge = FeedloomBridge(containerDirectory: tempDir)

        // Seed pending bookmarks file in the container
        let seedBookmarks = [
            FeedloomBookmark(
                url: "https://pointfree.co/episodes/ep280-metal-shaders",
                title: "Point-Free: Metal Shaders in SwiftUI",
                notes: "Dense architecture for shaders",
                tags: ["swiftui", "metal", "graphics"]
            ),
            FeedloomBookmark(
                url: "https://apple.com/ios-whats-new",
                title: "What's New in iOS",
                notes: "Overview of new system APIs",
                tags: ["apple", "ios"]
            )
        ]
        let data = try JSONEncoder().encode(seedBookmarks)
        try data.write(to: tempDir.appendingPathComponent("pendingBookmarks.json"))

        // Search for topic "metal"
        let suggestions = bridge.findReadingSuggestions(for: "metal", keywords: ["swiftui", "shaders"])
        XCTAssertEqual(suggestions.count, 1)
        XCTAssertEqual(suggestions.first?.title, "Point-Free: Metal Shaders in SwiftUI")
        XCTAssertEqual(suggestions.first?.url, "https://pointfree.co/episodes/ep280-metal-shaders")
    }

    func testSaveToFeedloomWritesToPendingBookmarksFile() throws {
        let bridge = FeedloomBridge(containerDirectory: tempDir)

        try bridge.saveToFeedloom(
            url: "https://developer.apple.com/documentation/appintents",
            title: "App Intents Documentation",
            notes: "Authoritative Apple reference",
            tags: ["apple", "appintents", "swift"]
        )

        let pendingFile = tempDir.appendingPathComponent("pendingBookmarks.json")
        XCTAssertTrue(FileManager.default.fileExists(atPath: pendingFile.path))

        let data = try Data(contentsOf: pendingFile)
        let saved = try JSONDecoder().decode([FeedloomBookmark].self, from: data)
        XCTAssertEqual(saved.count, 1)
        XCTAssertEqual(saved.first?.title, "App Intents Documentation")
        XCTAssertEqual(saved.first?.url, "https://developer.apple.com/documentation/appintents")
    }

    func testSaveToFeedloomAppendsToExistingPendingBookmarks() throws {
        let bridge = FeedloomBridge(containerDirectory: tempDir)

        try bridge.saveToFeedloom(
            url: "https://link1.test",
            title: "Link One",
            notes: "Note 1",
            tags: ["test"]
        )
        try bridge.saveToFeedloom(
            url: "https://link2.test",
            title: "Link Two",
            notes: "Note 2",
            tags: ["test"]
        )

        let pendingFile = tempDir.appendingPathComponent("pendingBookmarks.json")
        let data = try Data(contentsOf: pendingFile)
        let saved = try JSONDecoder().decode([FeedloomBookmark].self, from: data)
        XCTAssertEqual(saved.count, 2)
        XCTAssertEqual(saved[0].title, "Link One")
        XCTAssertEqual(saved[1].title, "Link Two")
    }

    func testEmptyContainerReturnsZeroSuggestionsGracefully() {
        let bridge = FeedloomBridge(containerDirectory: tempDir)
        let suggestions = bridge.findReadingSuggestions(for: "nonexistent", keywords: [])
        XCTAssertTrue(suggestions.isEmpty)
    }
}
