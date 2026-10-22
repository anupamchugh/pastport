import Foundation

/// One image from the local Photos library, reduced to the facts the clusterer needs.
/// Built by a PhotoKit provider in the app; built by hand in tests. No pixels here.
public struct PhotoRecord {
    public let time: Date
    public let isScreenshot: Bool
    public let labels: [String]

    public init(time: Date, isScreenshot: Bool, labels: [String]) {
        self.time = time
        self.isScreenshot = isScreenshot
        self.labels = labels
    }
}

/// A burst of photo activity — the photo-side sibling of a history thread. Counts and
/// scene labels are aggregated deterministically; nothing here touches a model.
public struct PhotoEvent: Sendable, Equatable {
    public let start: Date
    public let end: Date
    public let photoCount: Int
    public let screenshotCount: Int
    public let labels: [String]
}

public enum PhotoEvents {
    public static func statusLine(for error: PhotoLibraryError) -> String {
        switch error {
        case .empty:
            return "No photo activity was found in the window."
        case .denied:
            return "Photo activity is unavailable because Photos access is denied."
        case .unavailable:
            return "Photo activity is unavailable; Photos permission was not requested."
        case .invalidLimit:
            return "Photo activity is unavailable because the requested limit is invalid."
        }
    }

    /// The line shown after a photo read: what the read covered, the newest-500 cut when the
    /// window held more, and the limited-access note. Counts come from data, never a model.
    public static func statusLine(for read: PhotoRead) -> String {
        var lines = ["Photos are checked on this device for scene labels; screenshots are counted only. Up to 500 images."]
        if read.isTruncated {
            lines.append("Showing the newest \(read.records.count) of \(read.totalInWindow) photos in this window")
        }
        if read.isLimitedAccess {
            lines.append("Counting only the photos you shared with Pastport")
        }
        return lines.joined(separator: "\n")
    }

    /// Groups records into events: a new event starts when the quiet stretch since the
    /// previous image exceeds `gap` (default 36h — survives a sleep, splits separate trips).
    public static func cluster(_ records: [PhotoRecord],
                               gap: TimeInterval = 36 * 3600) -> [PhotoEvent] {
        struct Draft {
            var start: Date
            var end: Date
            var photos = 0
            var shots = 0
            var labelCounts: [String: Int] = [:]

            func sealed() -> PhotoEvent {
                let ranked = labelCounts.sorted {
                    $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key
                }.map(\.key)
                return PhotoEvent(start: start, end: end, photoCount: photos,
                                  screenshotCount: shots, labels: ranked)
            }
        }

        var events: [PhotoEvent] = []
        var draft: Draft?
        for record in records.sorted(by: { $0.time < $1.time }) {
            var current: Draft
            if let open = draft, record.time.timeIntervalSince(open.end) < gap {
                current = open
                current.end = record.time
            } else {
                if let open = draft { events.append(open.sealed()) }
                current = Draft(start: record.time, end: record.time)
            }
            if record.isScreenshot { current.shots += 1 } else { current.photos += 1 }
            for label in record.labels { current.labelCounts[label, default: 0] += 1 }
            draft = current
        }
        if let open = draft { events.append(open.sealed()) }
        return events
    }

    /// Small, deterministic evidence lines for the brief and CLI. Screenshot pixels
    /// never enter this representation; only the provider's counts and labels do.
    public static func briefLines(_ events: [PhotoEvent]) -> [String] {
        let formatter = ISO8601DateFormatter()
        return events.prefix(6).map { event in
            let range = formatter.string(from: event.start) == formatter.string(from: event.end)
                ? formatter.string(from: event.start)
                : "\(formatter.string(from: event.start)) to \(formatter.string(from: event.end))"
            let labelText = event.labels.isEmpty ? "none" : event.labels.prefix(5).joined(separator: ", ")
            return "\(range): \(event.photoCount) photos, \(event.screenshotCount) screenshots; labels: \(labelText)"
        }
    }
}
