import XCTest
@testable import PastportKit

final class GitHubHistoryTests: XCTestCase {
    func testFindsRecentUniqueRepositoriesWithoutQueryOrNonGitHubLinks() {
        let t = Date(timeIntervalSince1970: 1_000)
        let visits = [
            Visit(time: t, title: "issue", url: "https://github.com/Owner/Repo/issues/1?token=secret"),
            Visit(time: t.addingTimeInterval(-1), title: "root", url: "https://github.com/owner/repo"),
            Visit(time: t.addingTimeInterval(-2), title: "other", url: "https://github.com/other/project/tree/main"),
            Visit(time: t, title: "spoof", url: "https://github.com.example.org/a/b"),
            Visit(time: t, title: "search", url: "https://github.com/search/advanced"),
            Visit(time: t, title: "profile", url: "https://github.com/someone"),
        ]
        let repos = GitHubHistory.repositories(in: visits)
        XCTAssertEqual(repos.map(\.name), ["Owner/Repo", "other/project"])
        XCTAssertEqual(repos.first?.url.absoluteString, "https://github.com/Owner/Repo")
        XCTAssertEqual(GitHubHistory.repositories(in: visits, limit: 1).count, 1)
        XCTAssertTrue(GitHubHistory.repositories(in: visits, limit: 0).isEmpty)
    }
}
