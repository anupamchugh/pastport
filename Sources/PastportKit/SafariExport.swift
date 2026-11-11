import Foundation

/// Why a Safari export was refused. Every case leaves the previous timeline untouched and none of the
/// messages names a file or shows a row, so they are safe to show.
public enum SafariExportError: Error, Equatable, CustomStringConvertible {
    case tooLarge
    case unsafeArchive
    case notAnArchive
    case noHistory
    case unsupportedMetadata
    case malformedHistory
    case cancelled

    public var description: String {
        switch self {
        case .tooLarge: "That export is larger than Pastport reads (50 MB). Nothing was imported."
        case .unsafeArchive: "That archive is not a safe Safari export. Nothing was imported."
        case .notAnArchive: "Choose the ZIP file Safari exported. Nothing was imported."
        case .noHistory: "No Safari history was found in that export. Nothing was imported."
        case .unsupportedMetadata: "That export is not from Safari history. Nothing was imported."
        case .malformedHistory: "The history in that export could not be read. Nothing was imported."
        case .cancelled: "Import cancelled. Nothing was imported."
        }
    }
}

/// What a Safari export yielded, already scrubbed: no query strings, fragments or redirect URLs.
public struct SafariExportResult: Sendable {
    public let visits: [Visit]
    /// History files read (one per Safari profile).
    public let profiles: Int
    /// Rows that carried a usable page, before the row cap and de-duplication.
    public let rowsRead: Int
    /// True when the row cap cut the history; counts and totals are then lower bounds.
    public let isPartial: Bool
}

/// Reads the history out of a ZIP made by Safari's "Export Browsing Data". It works on the bytes in memory,
/// opens only files that look like history, and keeps nothing of the archive.
public enum SafariExport {
    public static let maxRows = 100_000
    public static let maxFieldBytes = 8 * 1024
    public static let sourceLabel = "Safari export · imported on this device"

    public static func read(from url: URL, limits: ZipLimits = .safariExport,
                            maxRows: Int = SafariExport.maxRows) throws -> SafariExportResult {
        try read(archive: try open { try ZipArchive(contentsOf: url, limits: limits) }, maxRows: maxRows)
    }

    public static func read(bytes: Data, limits: ZipLimits = .safariExport,
                            maxRows: Int = SafariExport.maxRows) throws -> SafariExportResult {
        try read(archive: try open { try ZipArchive(bytes: bytes, limits: limits) }, maxRows: maxRows)
    }

    private static func open(_ make: () throws -> ZipArchive) throws -> ZipArchive {
        do { return try make() } catch let error as ZipError {
            switch error {
            case .tooLarge: throw SafariExportError.tooLarge
            case .malformed: throw SafariExportError.notAnArchive
            case .unsafe, .encrypted, .unsupportedCompression: throw SafariExportError.unsafeArchive
            }
        }
    }

    private static func read(archive: ZipArchive, maxRows: Int) throws -> SafariExportResult {
        let candidates = archive.entries.filter { !$0.isDirectory && isHistoryName($0.name) }
        guard !candidates.isEmpty else { throw SafariExportError.noHistory }

        var rows: [Row] = []
        var profiles = 0
        var sawWrongMetadata = false
        for entry in candidates {
            let data: Data
            do { data = try archive.data(for: entry) } catch { throw SafariExportError.unsafeArchive }
            let file: HistoryFile
            do { file = try JSONDecoder().decode(HistoryFile.self, from: data) } catch {
                throw SafariExportError.malformedHistory
            }
            guard file.metadata.dataType == "history",
                  ["Safari", "Safari Technology Preview"].contains(file.metadata.browserName) else {
                sawWrongMetadata = true
                continue
            }
            profiles += 1
            rows.append(contentsOf: (file.history ?? []).compactMap(\.usable))
        }
        guard profiles > 0 else { throw sawWrongMetadata ? SafariExportError.unsupportedMetadata : SafariExportError.noHistory }
        guard !rows.isEmpty else { throw SafariExportError.noHistory }

        let rowsRead = rows.count
        // Newest first, so a cap drops the oldest rows. Then one visit per page, keeping its latest time.
        rows.sort { $0.time > $1.time }
        let isPartial = rows.count > maxRows
        if isPartial { rows.removeSubrange(maxRows...) }
        var seen = Set<String>()
        var visits: [Visit] = []
        for row in rows {
            let visit = Visit(time: row.time, title: row.title, url: row.url)
            guard seen.insert(visit.cleanURL).inserted else { continue }
            visits.append(Visit(time: row.time, title: row.title, url: visit.cleanURL))
        }
        return SafariExportResult(visits: visits, profiles: profiles, rowsRead: rowsRead, isPartial: isPartial)
    }

    /// Safari localizes the file names but keeps `History` as the stem in English. Other languages are
    /// not guessed: a name that is not recognized is never opened.
    static func isHistoryName(_ name: String) -> Bool {
        let base = name.split(separator: "/").last.map(String.init) ?? name
        let lower = base.lowercased()
        return lower.hasPrefix("history") && lower.hasSuffix(".json")
    }

    // MARK: Wire format (only the fields Pastport uses; everything else is ignored)

    private struct HistoryFile: Decodable {
        struct Metadata: Decodable {
            let browserName: String
            let dataType: String
            enum CodingKeys: String, CodingKey { case browserName = "browser_name", dataType = "data_type" }
        }
        let metadata: Metadata
        let history: [Entry]?
    }

    private struct Entry: Decodable {
        let url: String?
        let title: String?
        let timeUsec: Int64?
        /// Present on a redirect hop that is not itself a page. Only its presence is read, never its value.
        let hasDestination: Bool

        enum CodingKeys: String, CodingKey {
            case url, title, timeUsec = "time_usec", destination = "destination_url"
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            url = try? c.decode(String.self, forKey: .url)
            title = try? c.decode(String.self, forKey: .title)
            timeUsec = try? c.decode(Int64.self, forKey: .timeUsec)
            hasDestination = c.contains(.destination)
        }

        var usable: Row? {
            guard !hasDestination, let url, let timeUsec, timeUsec > 0,
                  url.utf8.count <= SafariExport.maxFieldBytes,
                  let parts = URLComponents(string: url), let scheme = parts.scheme?.lowercased(),
                  scheme == "http" || scheme == "https", let host = parts.host, !host.isEmpty
            else { return nil }
            let time = Date(timeIntervalSince1970: Double(timeUsec) / 1_000_000)
            guard time <= Date.now.addingTimeInterval(86_400) else { return nil }
            var title = title ?? ""
            if title.utf8.count > SafariExport.maxFieldBytes { title = String(title.prefix(SafariExport.maxFieldBytes / 4)) }
            return Row(time: time, title: title, url: url)
        }
    }

    private struct Row {
        let time: Date
        let title: String
        let url: String
    }
}

/// A session-only history source for an imported Safari export. The snapshot lives in memory, is scrubbed
/// when it is set, and is gone after `clear()`; nothing is written to disk.
public final class ImportedHistorySource: HistorySource, @unchecked Sendable {
    private let lock = NSLock()
    private var result: SafariExportResult?

    public init() {}

    public var isLoaded: Bool { lock.withLock { result != nil } }

    public func load(_ result: SafariExportResult) { lock.withLock { self.result = result } }

    public func clear() { lock.withLock { result = nil } }

    public func snapshot(days: Int?) async throws -> HistorySnapshot {
        guard let result = lock.withLock({ result }) else { throw SafariExportError.noHistory }
        var visits = result.visits
        if let days {
            let cutoff = Date.now.addingTimeInterval(-Double(days) * 86_400)
            visits = visits.filter { $0.time >= cutoff }
        }
        return HistorySnapshot(visits: visits, sourceCount: result.profiles, sourceRows: result.rowsRead,
                               isComplete: !result.isPartial, sourceLabel: SafariExport.sourceLabel)
    }
}
