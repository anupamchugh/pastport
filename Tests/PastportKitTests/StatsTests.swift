import Foundation
import Testing
@testable import PastportKit

@Suite("Stats")
struct StatsTests {
    @Test("Computes categories, 24 hour buckets, and top hosts")
    func computes() {
        let base = Date(timeIntervalSince1970: 1_000_000)
        let visits = [
            Visit(time: base, title: "a", url: "https://github.com/x"),
            Visit(time: base, title: "b", url: "https://github.com/y"),
            Visit(time: base, title: "c", url: "https://ok.ru/video/1"),
            Visit(time: base, title: "d", url: "https://news.example.com/z"),
        ]
        let stats = Stats.compute(from: visits, verticals: Verticals.defaults)
        #expect(stats.total == 4)
        #expect(stats.categories.first?.name == "Dev")     // github ×2 leads
        #expect(stats.categories.contains { $0.name == "Other" })
        #expect(stats.hours.count == 24)
        #expect(stats.topHosts.first?.host == "github.com")
        #expect(stats.topHosts.first?.visits == 2)
    }
}
