import Foundation

/// A structured link crawled from a research destination page.
public struct WebCrawledLink: Identifiable, Sendable, Codable, Equatable {
    public var id: String { url }
    public let url: String
    public let title: String
    public let score: Double

    public init(url: String, title: String, score: Double) {
        self.url = url
        self.title = title
        self.score = score
    }
}

/// Lightweight, deterministic link crawler tool for extracting and ranking outbound hyperlinks
/// from HTML pages without loading web views or executing JavaScript.
public final class WebLinkCrawlerTool: Sendable {
    public init() {}

    /// Extracts hyperlinks from HTML text, normalizes relative URLs against baseURL,
    /// removes tracking parameters, and ranks them by topic relevance.
    public func extractLinks(fromHTML html: String, baseURL: URL, targetTopic: String) -> [WebCrawledLink] {
        // Pattern: <a\s+[^>]*href=["']([^"']+)["'][^>]*>(.*?)<\/a>
        let pattern = #"<a\s+[^>]*href=["']([^"']+)["'][^>]*>(.*?)<\/a>"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else {
            return []
        }

        let nsString = html as NSString
        let matches = regex.matches(in: html, options: [], range: NSRange(location: 0, length: nsString.length))

        var candidateLinks: [WebCrawledLink] = []
        var seenURLs = Set<String>()

        let topicTerms = targetTopic.lowercased()
            .split(separator: " ")
            .map { String($0) }
            .filter { $0.count >= 2 }

        for match in matches {
            guard match.numberOfRanges >= 3 else { continue }
            let rawHref = nsString.substring(with: match.range(at: 1)).trimmingCharacters(in: .whitespacesAndNewlines)
            let rawTitle = nsString.substring(with: match.range(at: 2))

            // Strip inner HTML tags from title
            let cleanTitle = stripHTMLTags(from: rawTitle).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cleanTitle.isEmpty else { continue }

            // Ignore non-http links
            if rawHref.lowercased().hasPrefix("mailto:") ||
               rawHref.lowercased().hasPrefix("tel:") ||
               rawHref.lowercased().hasPrefix("javascript:") ||
               rawHref == "#" {
                continue
            }

            // Normalize URL
            guard let resolvedURL = resolve(href: rawHref, baseURL: baseURL) else { continue }
            let cleanURL = clean(url: resolvedURL)
            guard !seenURLs.contains(cleanURL) else { continue }
            seenURLs.insert(cleanURL)

            // Calculate relevance score
            var score = 1.0
            let titleLower = cleanTitle.lowercased()
            let urlLower = cleanURL.lowercased()

            for term in topicTerms {
                if titleLower.contains(term) {
                    score += 5.0
                }
                if urlLower.contains(term) {
                    score += 2.0
                }
            }

            // Demote generic navigation boilerplate
            let boilerplate = ["terms", "privacy", "about us", "contact", "careers", "sign in", "login", "cookie"]
            if boilerplate.contains(where: { titleLower.contains($0) }) {
                score -= 3.0
            }

            candidateLinks.append(WebCrawledLink(url: cleanURL, title: cleanTitle, score: score))
        }

        return candidateLinks.sorted { $0.score > $1.score }
    }

    // MARK: - Cleaning Helpers

    private func resolve(href: String, baseURL: URL) -> URL? {
        if let direct = URL(string: href), direct.scheme != nil {
            return direct
        }
        return URL(string: href, relativeTo: baseURL)?.absoluteURL
    }

    private func clean(url: URL) -> String {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: true) else {
            return url.absoluteString
        }

        // Remove tracking parameters
        if let queryItems = components.queryItems {
            let filtered = queryItems.filter { item in
                let name = item.name.lowercased()
                return !name.hasPrefix("utm_") && name != "ref" && name != "fbclid" && name != "gclid"
            }
            components.queryItems = filtered.isEmpty ? nil : filtered
        }

        // Remove fragment anchors
        components.fragment = nil

        return components.url?.absoluteString ?? url.absoluteString
    }

    private func stripHTMLTags(from string: String) -> String {
        string.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
    }
}
