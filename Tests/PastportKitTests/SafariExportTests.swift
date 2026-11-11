import Compression
import Foundation
import Testing
@testable import PastportKit

/// Builds ZIP bytes for fictional exports. `lyingSize` writes a smaller declared size than the data inflates to.
private struct ZipFixture {
    struct Item {
        var name: String
        var data: Data
        var deflate = true
        var unixMode: UInt32?
        var flags: UInt16 = 0
        var lyingSize: Int?
        var rawCompressed: Data?
    }

    var items: [Item] = []

    mutating func add(_ name: String, _ text: String, deflate: Bool = true) {
        items.append(Item(name: name, data: Data(text.utf8), deflate: deflate))
    }

    func build() -> Data {
        var out = Data()
        var central = Data()
        for item in items {
            let nameBytes = Data(item.name.utf8)
            let stored = item.rawCompressed ?? (item.deflate ? Self.deflate(item.data) : item.data)
            let declared = UInt32(item.lyingSize ?? item.data.count)
            let method: UInt16 = (item.deflate || item.rawCompressed != nil) ? 8 : 0
            let offset = UInt32(out.count)
            out.append(le32(0x0403_4B50)); out.append(le16(20)); out.append(le16(item.flags)); out.append(le16(method))
            out.append(le16(0)); out.append(le16(0)); out.append(le32(0))
            out.append(le32(UInt32(stored.count))); out.append(le32(declared))
            out.append(le16(UInt16(nameBytes.count))); out.append(le16(0))
            out.append(nameBytes); out.append(stored)

            central.append(le32(0x0201_4B50))
            central.append(le16(item.unixMode == nil ? 20 : (3 << 8) | 20)); central.append(le16(20))
            central.append(le16(item.flags)); central.append(le16(method))
            central.append(le16(0)); central.append(le16(0)); central.append(le32(0))
            central.append(le32(UInt32(stored.count))); central.append(le32(declared))
            central.append(le16(UInt16(nameBytes.count))); central.append(le16(0)); central.append(le16(0))
            central.append(le16(0)); central.append(le16(0))
            central.append(le32((item.unixMode ?? 0) << 16)); central.append(le32(offset))
            central.append(nameBytes)
        }
        let centralOffset = UInt32(out.count)
        out.append(central)
        out.append(le32(0x0605_4B50)); out.append(le16(0)); out.append(le16(0))
        out.append(le16(UInt16(items.count))); out.append(le16(UInt16(items.count)))
        out.append(le32(UInt32(central.count))); out.append(le32(centralOffset)); out.append(le16(0))
        return out
    }

    private func le16(_ v: UInt16) -> Data { Data([UInt8(v & 0xFF), UInt8(v >> 8)]) }
    private func le32(_ v: UInt32) -> Data { Data((0..<4).map { UInt8((v >> (8 * UInt32($0))) & 0xFF) }) }

    static func deflate(_ data: Data) -> Data {
        guard !data.isEmpty else { return Data() }
        var out = Data(count: data.count + 1024)
        let n: Int = out.withUnsafeMutableBytes { dst in
            data.withUnsafeBytes { src in
                compression_encode_buffer(dst.bindMemory(to: UInt8.self).baseAddress!, dst.count,
                                          src.bindMemory(to: UInt8.self).baseAddress!, data.count, nil, COMPRESSION_ZLIB)
            }
        }
        return out.prefix(n)
    }
}

private func historyJSON(browser: String = "Safari", type: String = "history", rows: [String]) -> String {
    """
    {"metadata":{"browser_name":"\(browser)","browser_version":"27.0","data_type":"\(type)","export_time_usec":1,"schema_version":1},
     "history":[\(rows.joined(separator: ","))]}
    """
}

private func row(_ url: String, title: String? = nil, usec: Int64, extra: String = "") -> String {
    let t = title.map { ",\"title\":\"\($0)\"" } ?? ""
    return "{\"url\":\"\(url)\"\(t),\"time_usec\":\(usec),\"visits_count\":1\(extra)}"
}

private let day: Int64 = 86_400 * 1_000_000
private let base: Int64 = 1_760_000_000 * 1_000_000   // 9 Oct 2025, fictional

@Suite("Safari export import")
struct SafariExportTests {
    @Test("rows become scrubbed, de-duplicated visits, newest first, with redirect hops dropped")
    func scrubsAndDeduplicates() throws {
        var zip = ZipFixture()
        zip.add("History.json", historyJSON(rows: [
            row("https://example.com/a?token=secret#frag", title: "A old", usec: base),
            row("https://example.com/a?other=1", title: "A new", usec: base + 2 * day),
            row("https://example.org/b", title: "B", usec: base + day),
            row("https://hop.example.net/go", usec: base + 3 * day, extra: ",\"destination_url\":\"https://example.org/b\",\"destination_time_usec\":1"),
        ]))
        let result = try SafariExport.read(bytes: zip.build())
        #expect(result.visits.map(\.url) == ["https://example.com/a", "https://example.org/b"])
        #expect(result.visits.map(\.title) == ["A new", "B"])
        #expect(result.profiles == 1)
        #expect(!result.isPartial)
        #expect(result.visits.allSatisfy { !$0.url.contains("?") && !$0.url.contains("#") })
    }

    @Test("every profile's history file is read, named with a suffix or not")
    func mergesProfiles() throws {
        var zip = ZipFixture()
        zip.add("History.json", historyJSON(rows: [row("https://example.com/one", usec: base)]))
        zip.add("History (Work).json", historyJSON(browser: "Safari Technology Preview",
                                                    rows: [row("https://example.com/two", usec: base + day)]))
        let result = try SafariExport.read(bytes: zip.build())
        #expect(result.profiles == 2)
        #expect(result.visits.count == 2)
    }

    @Test("password, card and extension files are never opened")
    func ignoresSensitiveFiles() throws {
        var zip = ZipFixture()
        zip.add("History.json", historyJSON(rows: [row("https://example.com/ok", usec: base)]))
        // Bytes that cannot be inflated: opening any of these would fail the import.
        for name in ["Passwords.csv", "PaymentCards.json", "Extensions.json", "Bookmarks.html"] {
            zip.items.append(.init(name: name, data: Data("secret".utf8), rawCompressed: Data([0xFF, 0xFF, 0xFF, 0xFF])))
        }
        let result = try SafariExport.read(bytes: zip.build())
        #expect(result.visits.map(\.url) == ["https://example.com/ok"])
    }

    @Test("a history file from another browser or another data type is refused")
    func refusesOtherMetadata() {
        var other = ZipFixture()
        other.add("History.json", historyJSON(browser: "Other", rows: [row("https://example.com/x", usec: base)]))
        #expect(throws: SafariExportError.unsupportedMetadata) { try SafariExport.read(bytes: other.build()) }
        var typed = ZipFixture()
        typed.add("History.json", historyJSON(type: "extensions", rows: []))
        #expect(throws: SafariExportError.unsupportedMetadata) { try SafariExport.read(bytes: typed.build()) }
    }

    @Test("rows without a web address or a sane time are dropped, and nothing usable is refused")
    func dropsUnusableRows() throws {
        var zip = ZipFixture()
        zip.add("History.json", historyJSON(rows: [
            row("javascript:alert(1)", usec: base), row("file:///private/thing", usec: base),
            row("https://example.com/zero", usec: 0), row("not a url", usec: base),
            row("https://example.com/good", title: "Good", usec: base),
        ]))
        #expect(try SafariExport.read(bytes: zip.build()).visits.map(\.url) == ["https://example.com/good"])
        var empty = ZipFixture()
        empty.add("History.json", historyJSON(rows: [row("ftp://example.com/x", usec: base)]))
        #expect(throws: SafariExportError.noHistory) { try SafariExport.read(bytes: empty.build()) }
    }

    @Test("the row cap keeps the newest rows and says the result is partial")
    func rowCapIsPartial() throws {
        var zip = ZipFixture()
        zip.add("History.json", historyJSON(rows: (0..<5).map { row("https://example.com/p\($0)", usec: base + Int64($0) * day) }))
        let result = try SafariExport.read(bytes: zip.build(), maxRows: 3)
        #expect(result.isPartial)
        #expect(result.visits.map(\.url) == ["https://example.com/p4", "https://example.com/p3", "https://example.com/p2"])
        #expect(result.rowsRead == 5)
    }

    @Test("unsafe archives are refused before anything is read")
    func refusesUnsafeArchives() {
        func refused(_ expected: SafariExportError = .unsafeArchive, limits: ZipLimits = .safariExport,
                     _ build: (inout ZipFixture) -> Void) {
            var zip = ZipFixture()
            zip.add("History.json", historyJSON(rows: [row("https://example.com/ok", usec: base)]))
            build(&zip)
            #expect(throws: expected) { try SafariExport.read(bytes: zip.build(), limits: limits) }
        }
        refused { $0.add("../escape.txt", "x") }
        refused { $0.add("/etc/absolute.txt", "x") }
        refused { $0.add("a/../../b.txt", "x") }
        refused { $0.items.append(.init(name: "link.json", data: Data("History.json".utf8), deflate: false, unixMode: 0o120777)) }
        refused { $0.add("history.JSON", "{}") }                                    // duplicate of History.json, any case
        refused { $0.items[0].flags = 1 }                                           // encrypted history
        refused(limits: ZipLimits(maxArchiveBytes: 50_000_000, maxUncompressedBytes: 10, maxEntries: 10)) { _ in }
        refused(limits: ZipLimits(maxArchiveBytes: 50_000_000, maxUncompressedBytes: 200_000_000, maxEntries: 1)) { $0.add("two.txt", "x") }
        refused(.tooLarge, limits: ZipLimits(maxArchiveBytes: 20, maxUncompressedBytes: 200_000_000, maxEntries: 10)) { _ in }
        // Inflates past its declared size: a decompression bomb in miniature.
        refused { $0.items[0].lyingSize = 5 }
    }

    @Test("something that is not a ZIP is refused, and a ZIP with no history says so")
    func refusesNonArchives() {
        #expect(throws: SafariExportError.notAnArchive) { try SafariExport.read(bytes: Data("hello".utf8)) }
        #expect(throws: SafariExportError.notAnArchive) { try SafariExport.read(bytes: Data(count: 4_096)) }
        var zip = ZipFixture()
        zip.add("Bookmarks.html", "<html></html>")
        #expect(throws: SafariExportError.noHistory) { try SafariExport.read(bytes: zip.build()) }
        var bad = ZipFixture()
        bad.add("History.json", "{not json")
        #expect(throws: SafariExportError.malformedHistory) { try SafariExport.read(bytes: bad.build()) }
    }

    @Test("an archive made by the system zip tool reads the same")
    func readsASystemZip() throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: "pastport-zip-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let json = historyJSON(rows: (0..<200).map { row("https://example.com/page/\($0)?x=\($0)", title: "Page \($0)", usec: base + Int64($0) * day) })
        try Data(json.utf8).write(to: dir.appending(path: "History.json"))
        let archive = dir.appending(path: "export.zip")
        let zip = Process()
        zip.executableURL = URL(filePath: "/usr/bin/zip")
        zip.currentDirectoryURL = dir
        zip.arguments = ["-q", "export.zip", "History.json"]
        try zip.run(); zip.waitUntilExit()
        #expect(zip.terminationStatus == 0)
        let result = try SafariExport.read(from: archive)
        #expect(result.visits.count == 200)
        #expect(result.visits.first?.url == "https://example.com/page/199")
    }

    @Test("an imported source answers with its label and window, and is empty after clear")
    func importedSourceLifecycle() async throws {
        let now = Date.now
        let result = SafariExportResult(
            visits: [Visit(time: now, title: "New", url: "https://example.com/new"),
                     Visit(time: now.addingTimeInterval(-40 * 86_400), title: "Old", url: "https://example.com/old")],
            profiles: 1, rowsRead: 2, isPartial: true)
        let source = ImportedHistorySource()
        await #expect(throws: SafariExportError.noHistory) { try await source.snapshot(days: 90) }
        source.load(result)
        let recent = try await source.snapshot(days: 30)
        #expect(recent.visits.map(\.title) == ["New"])
        #expect(!recent.isComplete)
        #expect(recent.scope.contains("Safari export · imported on this device"))
        #expect(try await source.snapshot(days: nil).visits.count == 2)
        source.clear()
        #expect(!source.isLoaded)
        await #expect(throws: SafariExportError.noHistory) { try await source.snapshot(days: nil) }
    }
}
