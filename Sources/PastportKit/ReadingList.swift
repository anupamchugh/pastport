import Foundation

/// A page from Safari's Reading List, as the export lists it. Query strings and fragments are already gone.
public struct ReadingListItem: Identifiable, Sendable, Equatable, Hashable {
    public let title: String
    public let url: String
    public var id: String { url }

    public init(title: String, url: String) {
        self.title = title
        self.url = url
    }

    public var host: String { Visit(time: .distantPast, title: title, url: url).host }
}

/// Reads the Reading List out of the `Bookmarks.html` Safari writes into an export (Netscape bookmark format).
/// Only the folder identified as `com.apple.ReadingList` is read; every other bookmark is ignored, so a
/// bookmark the person filed anywhere else never reaches Pastport.
public enum ReadingListParser {
    public static let maxItems = 10_000
    static let folderMarker = "com.apple.readinglist"

    private static let tag = try! NSRegularExpression(pattern: #"<(/?)(DL|H3|A)\b([^>]*)>"#, options: [.caseInsensitive])
    private static let href = try! NSRegularExpression(pattern: #"\bhref\s*=\s*(?:"([^"]*)"|'([^']*)')"#, options: [.caseInsensitive])

    public static func parse(_ html: String) -> [ReadingListItem] {
        let text = html as NSString
        let tags = tag.matches(in: html, range: NSRange(location: 0, length: text.length))
        var items: [ReadingListItem] = []
        var seen = Set<String>()
        var depth = 0
        var readingListDepth: Int?
        var folderPending = false

        for (index, match) in tags.enumerated() {
            let closing = text.substring(with: match.range(at: 1)) == "/"
            let name = text.substring(with: match.range(at: 2)).uppercased()
            let attributes = text.substring(with: match.range(at: 3))
            switch (name, closing) {
            case ("H3", false):
                folderPending = attributes.lowercased().contains(folderMarker)
            case ("DL", false):
                depth += 1
                if folderPending { readingListDepth = depth; folderPending = false }
            case ("DL", true):
                if readingListDepth == depth { readingListDepth = nil }
                depth = max(0, depth - 1)
            case ("A", false):
                guard readingListDepth != nil, items.count < maxItems,
                      let address = value(of: href, in: attributes) else { continue }
                let titleStart = match.range.location + match.range.length
                let titleEnd = tags.dropFirst(index + 1).first.map { $0.range.location } ?? text.length
                let raw = text.substring(with: NSRange(location: titleStart, length: max(0, titleEnd - titleStart)))
                if let item = makeItem(address: decode(address), title: decode(raw)), seen.insert(item.url).inserted {
                    items.append(item)
                }
            default:
                break
            }
        }
        return items
    }

    private static func makeItem(address: String, title: String) -> ReadingListItem? {
        guard address.utf8.count <= SafariExport.maxFieldBytes,
              let parts = URLComponents(string: address), let scheme = parts.scheme?.lowercased(),
              scheme == "http" || scheme == "https", let host = parts.host, !host.isEmpty else { return nil }
        let clean = Visit(time: .distantPast, title: "", url: address).cleanURL
        var shown = title.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        if shown.utf8.count > SafariExport.maxFieldBytes { shown = String(shown.prefix(SafariExport.maxFieldBytes / 4)) }
        return ReadingListItem(title: shown.isEmpty ? host : shown, url: clean)
    }

    private static func value(of regex: NSRegularExpression, in text: String) -> String? {
        let ns = text as NSString
        guard let match = regex.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)) else { return nil }
        for group in 1..<match.numberOfRanges where match.range(at: group).location != NSNotFound {
            return ns.substring(with: match.range(at: group))
        }
        return nil
    }

    /// The few entities a bookmarks file uses: the named five and numeric references.
    static func decode(_ text: String) -> String {
        guard text.contains("&") else { return text }
        let named = ["&amp;": "&", "&lt;": "<", "&gt;": ">", "&quot;": "\"", "&apos;": "'"]
        var result = text
        let numeric = try! NSRegularExpression(pattern: #"&#(x[0-9a-fA-F]+|[0-9]+);"#)
        let ns = result as NSString
        for match in numeric.matches(in: result, range: NSRange(location: 0, length: ns.length)).reversed() {
            let digits = ns.substring(with: match.range(at: 1))
            let code = digits.hasPrefix("x") ? UInt32(digits.dropFirst(), radix: 16) : UInt32(digits)
            if let code, let scalar = Unicode.Scalar(code) {
                result = (result as NSString).replacingCharacters(in: match.range, with: String(Character(scalar)))
            }
        }
        for (entity, plain) in named { result = result.replacingOccurrences(of: entity, with: plain) }
        return result
    }
}
