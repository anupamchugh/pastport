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

    func testConcurrentSavesKeepEveryRequestAndLeaveLegacyInboxIntact() async throws {
        let legacy = tempDir.appendingPathComponent("pendingBookmarks.json")
        let original = Data("not valid JSON".utf8)
        try original.write(to: legacy)
        let bridge = FeedloomBridge(containerDirectory: tempDir)
        try await withThrowingTaskGroup(of: Void.self) { group in
            for index in 0..<40 {
                group.addTask {
                    try bridge.saveToFeedloom(url: "https://example.com/\(index)", title: "\(index)", notes: "", tags: [])
                }
            }
            try await group.waitForAll()
        }
        let inbox = tempDir.appendingPathComponent("PendingLinkInbox")
        let files = try FileManager.default.contentsOfDirectory(at: inbox, includingPropertiesForKeys: nil)
        let entries = try files.flatMap { try JSONDecoder().decode([FeedloomBookmark].self, from: Data(contentsOf: $0)) }
        XCTAssertEqual(files.count, 40)
        XCTAssertEqual(Set(entries.map(\.url)).count, 40)
        XCTAssertEqual(try Data(contentsOf: legacy), original)
    }

    func testSuggestionsIncludeQueuedLink() throws {
        let bridge = FeedloomBridge(containerDirectory: tempDir)
        try bridge.saveToFeedloom(url: "https://example.com/swift", title: "Swift guide", notes: "", tags: [])
        XCTAssertEqual(bridge.findReadingSuggestions(for: "swift").map(\.title), ["Swift guide"])
    }

    func testEmptyContainerReturnsZeroSuggestionsGracefully() {
        let bridge = FeedloomBridge(containerDirectory: tempDir)
        let suggestions = bridge.findReadingSuggestions(for: "nonexistent", keywords: [])
        XCTAssertTrue(suggestions.isEmpty)
    }
}
