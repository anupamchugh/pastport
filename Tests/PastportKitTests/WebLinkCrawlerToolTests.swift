import Foundation
import XCTest
@testable import PastportKit

final class WebLinkCrawlerToolTests: XCTestCase {

    func testExtractsAndNormalizesOutboundLinksFromHTML() {
        let html = """
        <html>
        <body>
            <h1>Kyoto Travel Guide</h1>
            <p>Welcome to our travel portal.</p>
            <a href="https://japan-guide.com/e/e2158.html?utm_source=social&ref=sidebar">Kyoto Top 10 Attractions</a>
            <a href="/transport/shinkansen-timetable">Shinkansen Timetable & Fares</a>
            <a href="mailto:info@japan-guide.com">Contact Us</a>
            <a href="https://japan-guide.com/e/e2158.html#section2">Section Anchor</a>
            <a href="javascript:void(0)">Do Not Follow</a>
        </body>
        </html>
        """

        let crawler = WebLinkCrawlerTool()
        let links = crawler.extractLinks(
            fromHTML: html,
            baseURL: URL(string: "https://japan-guide.com")!,
            targetTopic: "kyoto"
        )

        // Valid http/https links only, stripped of tracking params and anchors
        XCTAssertEqual(links.count, 2)

        let first = links.first { $0.url.contains("e2158.html") }
        XCTAssertNotNil(first)
        XCTAssertEqual(first?.title, "Kyoto Top 10 Attractions")
        XCTAssertEqual(first?.url, "https://japan-guide.com/e/e2158.html") // cleaned of utm_source

        let relative = links.first { $0.url.contains("shinkansen-timetable") }
        XCTAssertNotNil(relative)
        XCTAssertEqual(relative?.url, "https://japan-guide.com/transport/shinkansen-timetable")
    }

    func testRanksLinksByRelevanceToTopic() {
        let html = """
        <div>
            <a href="https://apple.com/privacy">Apple Privacy Policy</a>
            <a href="https://developer.apple.com/metal">Metal Shaders & Graphics Architecture</a>
            <a href="https://developer.apple.com/swiftui">SwiftUI Declarative UI Framework</a>
        </div>
        """

        let crawler = WebLinkCrawlerTool()
        let links = crawler.extractLinks(
            fromHTML: html,
            baseURL: URL(string: "https://apple.com")!,
            targetTopic: "metal"
        )

        XCTAssertEqual(links.count, 3)
        // The link with "Metal" in anchor text should be ranked highest
        XCTAssertEqual(links[0].url, "https://developer.apple.com/metal")
        XCTAssertTrue(links[0].score > links[1].score)
    }

    func testIgnoresEmptyOrBoilerplateLinks() {
        let html = """
        <div>
            <a href="https://example.com/terms">Terms</a>
            <a href="https://example.com/privacy">Privacy</a>
            <a href="https://example.com">   </a>
            <a href="">Empty</a>
        </div>
        """

        let crawler = WebLinkCrawlerTool()
        let links = crawler.extractLinks(
            fromHTML: html,
            baseURL: URL(string: "https://example.com")!,
            targetTopic: "research"
        )

        // Empty text links and whitespace are dropped
        XCTAssertFalse(links.contains { $0.title.trimmingCharacters(in: .whitespaces).isEmpty })
    }
}
