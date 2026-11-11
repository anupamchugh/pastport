import Compression
import Foundation
import Testing
@testable import PastportKit

/// A minimal ZIP writer for fictional exports (deflate or stored; no flags).
private func zip(_ files: [(name: String, data: Data)]) -> Data {
    func le16(_ v: UInt16) -> Data { Data([UInt8(v & 0xFF), UInt8(v >> 8)]) }
    func le32(_ v: UInt32) -> Data { Data((0..<4).map { UInt8((v >> (8 * UInt32($0))) & 0xFF) }) }
    var out = Data(), central = Data()
    for file in files {
        let name = Data(file.name.utf8)
        let offset = UInt32(out.count)
        out.append(le32(0x0403_4B50)); out.append(le16(20)); out.append(le16(0)); out.append(le16(0))
        out.append(le16(0)); out.append(le16(0)); out.append(le32(0))
        out.append(le32(UInt32(file.data.count))); out.append(le32(UInt32(file.data.count)))
        out.append(le16(UInt16(name.count))); out.append(le16(0)); out.append(name); out.append(file.data)
        central.append(le32(0x0201_4B50)); central.append(le16(20)); central.append(le16(20))
        central.append(le16(0)); central.append(le16(0)); central.append(le16(0)); central.append(le16(0)); central.append(le32(0))
        central.append(le32(UInt32(file.data.count))); central.append(le32(UInt32(file.data.count)))
        central.append(le16(UInt16(name.count))); central.append(le16(0)); central.append(le16(0))
        central.append(le16(0)); central.append(le16(0)); central.append(le32(0)); central.append(le32(offset)); central.append(name)
    }
    let start = UInt32(out.count)
    out.append(central)
    out.append(le32(0x0605_4B50)); out.append(le16(0)); out.append(le16(0))
    out.append(le16(UInt16(files.count))); out.append(le16(UInt16(files.count)))
    out.append(le32(UInt32(central.count))); out.append(le32(start)); out.append(le16(0))
    return out
}

private let historyJSON = """
{"metadata":{"browser_name":"Safari","data_type":"history"},"history":[
 {"url":"https://example.com/seen?q=1","title":"Seen","time_usec":1760000000000000,"visits_count":1}]}
"""

private let bookmarksHTML = """
<!DOCTYPE NETSCAPE-Bookmark-file-1>
<META HTTP-EQUIV="Content-Type" CONTENT="text/html; charset=UTF-8">
<TITLE>Bookmarks</TITLE>
<H1>Bookmarks</H1>
<DL><p>
    <DT><H3 FOLDED ADD_DATE="1">Favorites</H3>
    <DL><p>
        <DT><A HREF="https://favorite.example/home">A favorite, not a reading list item</A>
    </DL><p>
    <DT><H3 FOLDED ID="com.apple.ReadingList">Reading List</H3>
    <DL><p>
        <DT><A HREF="https://read.example/article?utm_source=x&amp;token=SECRET#part">Fish &amp; chips: a &#39;history&#39;</A>
        <DT><A HREF="https://read.example/article?other=1">Same page, other query</A>
        <DT><A HREF="javascript:alert(1)">Not a web page</A>
        <DT><A HREF="https://other.example/long">Second</A>
    </DL><p>
    <DT><H3 FOLDED ADD_DATE="2">Work</H3>
    <DL><p>
        <DT><A HREF="https://work.example/board">Board</A>
    </DL><p>
</DL><p>
"""

@Suite("Reading List from the Safari export")
struct ReadingListTests {
    @Test("only the com.apple.ReadingList folder is read; other bookmarks never appear")
    func readsOnlyTheReadingListFolder() {
        let items = ReadingListParser.parse(bookmarksHTML)
        #expect(items.map(\.url) == ["https://read.example/article", "https://other.example/long"])
        #expect(items.first?.title == "Fish & chips: a 'history'", "entities in the title are decoded")
        #expect(!items.contains { $0.url.contains("favorite") || $0.url.contains("work.example") })
    }

    @Test("addresses lose query strings and fragments, repeats collapse, and non-web links are dropped")
    func scrubsAndDeduplicates() {
        let items = ReadingListParser.parse(bookmarksHTML)
        #expect(items.allSatisfy { !$0.url.contains("?") && !$0.url.contains("#") && !$0.url.contains("SECRET") })
        #expect(items.count == 2)
        #expect(items.first?.host == "read.example")
    }

    @Test("a file with no Reading List folder, or a broken one, yields nothing and does not crash")
    func noFolder() {
        #expect(ReadingListParser.parse("<DL><DT><H3>Favorites</H3><DL><DT><A HREF=\"https://a.example/\">A</A></DL></DL>").isEmpty)
        #expect(ReadingListParser.parse("").isEmpty)
        #expect(ReadingListParser.parse("<H3 ID=\"com.apple.ReadingList\">Reading List").isEmpty)
        #expect(ReadingListParser.parse("<A HREF=\"https://a.example/\">orphan</A>").isEmpty)
    }

    @Test("the number of items and the size of a title are bounded")
    func bounds() {
        let rows = (0..<ReadingListParser.maxItems + 50).map { "<DT><A HREF=\"https://r.example/\($0)\">\(String(repeating: "t", count: 20_000))</A>" }
        let html = "<DL><DT><H3 ID=\"com.apple.ReadingList\">Reading List</H3><DL>\(rows.joined())</DL></DL>"
        let items = ReadingListParser.parse(html)
        #expect(items.count == ReadingListParser.maxItems)
        #expect(items.allSatisfy { $0.title.utf8.count <= SafariExport.maxFieldBytes })
    }

    @Test("an export with history and bookmarks returns both; the ledger of opened files is exactly those two")
    func importerOpensOnlyHistoryAndBookmarks() throws {
        let junk = Data("not for Pastport".utf8)
        let bytes = zip([
            (name: "Passwords.csv", data: junk), (name: "PaymentCards.json", data: junk),
            (name: "Extensions.json", data: junk), (name: "Notes.txt", data: junk),
            (name: "History.json", data: Data(historyJSON.utf8)),
            (name: "Bookmarks.html", data: Data(bookmarksHTML.utf8)),
            (name: "Passwords.csv.bak", data: junk), (name: "Bookmarks.html.old", data: junk),
        ])
        var opened: [String] = []
        let result = try SafariExport.read(bytes: bytes, opened: { opened.append($0) })
        #expect(opened == ["History.json", "Bookmarks.html"])
        #expect(result.visits.map(\.url) == ["https://example.com/seen"])
        #expect(result.readingList.map(\.url) == ["https://read.example/article", "https://other.example/long"])
    }

    @Test("history fails before bookmarks are opened, and a broken Bookmarks.html costs only the Reading List")
    func bookmarksAreOptionalAndSecond() throws {
        var opened: [String] = []
        #expect(throws: SafariExportError.malformedHistory) {
            try SafariExport.read(bytes: zip([(name: "Bookmarks.html", data: Data(bookmarksHTML.utf8)),
                                              (name: "History.json", data: Data("{broken".utf8))]), opened: { opened.append($0) })
        }
        #expect(opened == ["History.json"], "Bookmarks.html is opened only after history was accepted")

        let notUTF8 = Data([0xFF, 0xFE, 0xFD, 0x00])
        let result = try SafariExport.read(bytes: zip([(name: "History.json", data: Data(historyJSON.utf8)),
                                                       (name: "Bookmarks.html", data: notUTF8)]))
        #expect(result.visits.count == 1 && result.readingList.isEmpty)
    }

    @Test("the imported source keeps the Reading List in memory only and drops it on clear")
    func sourceLifecycle() async throws {
        let item = ReadingListItem(title: "T", url: "https://r.example/a")
        let result = SafariExportResult(visits: [Visit(time: .now, title: "V", url: "https://v.example/")],
                                        profiles: 1, rowsRead: 1, isPartial: false, readingList: [item])
        let source = ImportedHistorySource()
        source.load(result)
        #expect(source.readingList == [item])
        source.clear()
        #expect(source.readingList.isEmpty)
    }
}
