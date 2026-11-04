import Foundation

/// A bookmark shared through the `group.com.anupamchugh.LinkVault` app-group container.
public struct FeedloomBookmark: Codable, Sendable, Equatable {
    public let url: String
    public let title: String
    public let notes: String
    public let tags: [String]
    public let timestamp: String?

    public init(url: String, title: String, notes: String, tags: [String], timestamp: String? = nil) {
        self.url = url
        self.title = title
        self.notes = notes
        self.tags = tags
        self.timestamp = timestamp
    }
}

/// A recommended reading item surfaced from the user's Feedloom vault matching an active intent thread.
public struct FeedloomSuggestion: Identifiable, Sendable, Equatable {
    public var id: String { url }
    public let url: String
    public let title: String
    public let notes: String
    public let matchedTopic: String
    public let score: Double

    public init(url: String, title: String, notes: String, matchedTopic: String, score: Double) {
        self.url = url
        self.title = title
        self.notes = notes
        self.matchedTopic = matchedTopic
        self.score = score
    }
}

/// Zero-cloud bridge between Pastport's detected intent threads and Feedloom (LinkVault).
/// Reads and writes to `group.com.anupamchugh.LinkVault` with zero network overhead.
///
/// **Privacy Invariant**: Zero private Safari history, search queries, or screenshot OCR content is written into
/// the App Group container. FeedloomBridge only reads publicly saved bookmarks from Feedloom's pending inbox to suggest
/// reading, and writes a URL to Feedloom only when the user explicitly triggers 'Save destination to Feedloom' or invokes an App Intent.
public final class FeedloomBridge: Sendable {
    public static let appGroupID = "group.com.anupamchugh.LinkVault"
    public static let sharedNotification = "com.anupamchugh.LinkVault.urlShared"

    private let customContainerDirectory: URL?

    public init(containerDirectory: URL? = nil) {
        self.customContainerDirectory = containerDirectory
    }

    /// The base container directory, either explicitly passed (in tests) or the security app group container.
    public var containerDirectory: URL? {
        if let custom = customContainerDirectory {
            return custom
        }
        return FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: Self.appGroupID)
    }

    /// Finds unread or saved bookmarks in Feedloom that match the browsing intent topic and related queries.
    public func findReadingSuggestions(for topic: String, keywords: [String] = []) -> [FeedloomSuggestion] {
        guard let container = containerDirectory else { return [] }
        let pendingFile = container.appendingPathComponent("pendingBookmarks.json")

        var bookmarks: [FeedloomBookmark] = []
        if let data = try? Data(contentsOf: pendingFile),
           let decoded = try? JSONDecoder().decode([FeedloomBookmark].self, from: data) {
            bookmarks.append(contentsOf: decoded)
        }

        // Include links queued by current Pastport and Feedloom share senders.
        let pendingInbox = container.appendingPathComponent("PendingLinkInbox", isDirectory: true)
        if let files = try? FileManager.default.contentsOfDirectory(at: pendingInbox, includingPropertiesForKeys: nil) {
            for file in files where file.pathExtension == "json" {
                if let data = try? Data(contentsOf: file),
                   let decoded = try? JSONDecoder().decode([FeedloomBookmark].self, from: data) {
                    bookmarks.append(contentsOf: decoded)
                }
            }
        }

        // Also check any inbox json files dropped by Threadmark claws
        let inboxDir = container.appendingPathComponent("Inbox")
        if let entries = try? FileManager.default.contentsOfDirectory(atPath: inboxDir.path) {
            for entry in entries where entry.hasPrefix("threadmark-claws-") && entry.hasSuffix(".json") {
                let fileURL = inboxDir.appendingPathComponent(entry)
                if let data = try? Data(contentsOf: fileURL),
                   let decoded = try? JSONDecoder().decode([FeedloomBookmark].self, from: data) {
                    bookmarks.append(contentsOf: decoded)
                }
            }
        }

        let searchTerms = ([topic] + keywords)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { $0.count >= 2 }

        var suggestions: [FeedloomSuggestion] = []
        for bookmark in bookmarks {
            let searchableText = (bookmark.title + " " + bookmark.notes + " " + bookmark.tags.joined(separator: " ") + " " + bookmark.url).lowercased()
            var matches = 0.0

            for term in searchTerms {
                if searchableText.contains(term) {
                    matches += (bookmark.title.lowercased().contains(term) ? 2.0 : 1.0)
                }
            }

            if matches > 0 {
                suggestions.append(FeedloomSuggestion(
                    url: bookmark.url,
                    title: bookmark.title,
                    notes: bookmark.notes,
                    matchedTopic: topic,
                    score: matches
                ))
            }
        }

        return suggestions.sorted { $0.score > $1.score }
    }

    /// Saves a research destination or intent link directly into Feedloom's pending inbox.
    public func saveToFeedloom(url: String, title: String, notes: String, tags: [String]) throws {
        guard let container = containerDirectory else {
            throw CLIError.msg("App group container '\(Self.appGroupID)' is unavailable.")
        }

        if !FileManager.default.fileExists(atPath: container.path) {
            try FileManager.default.createDirectory(at: container, withIntermediateDirectories: true)
        }

        // One atomically published file per request avoids read-modify-write races with
        // other senders. Feedloom's updated reader imports and removes each file separately.
        let inbox = container.appendingPathComponent("PendingLinkInbox", isDirectory: true)
        try FileManager.default.createDirectory(at: inbox, withIntermediateDirectories: true)
        let bookmark = FeedloomBookmark(
            url: url, title: title, notes: notes, tags: tags,
            timestamp: ISO8601DateFormatter().string(from: Date())
        )
        let file = inbox.appendingPathComponent("\(UUID().uuidString).json")
        try JSONEncoder().encode([bookmark]).write(to: file, options: [.atomic])

        // Post Darwin notification so Feedloom drains the inbox immediately if active
        #if canImport(CoreFoundation)
        let notificationName = Self.sharedNotification as CFString
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            CFNotificationName(notificationName),
            nil,
            nil,
            true
        )
        #endif
    }
}
