import Testing
@testable import PastportKit

@Suite("Pane layout")
struct PaneLayoutTests {
    @Test func compactShowsOnePane() {
        for tab in TimelineModel.Tab.allCases {
            #expect(PaneLayout.panes(for: tab, isRegularWidth: false) == [tab])
        }
    }

    @Test func regularTimelineAndAskShareTheScreen() {
        #expect(PaneLayout.panes(for: .trail, isRegularWidth: true) == [.trail, .ask])
        #expect(PaneLayout.panes(for: .ask, isRegularWidth: true) == [.trail, .ask])
    }

    @Test func regularAddAndPrivacyShareTheScreen() {
        #expect(PaneLayout.panes(for: .add, isRegularWidth: true) == [.add, .privacy])
        #expect(PaneLayout.panes(for: .privacy, isRegularWidth: true) == [.add, .privacy])
    }

    @Test func foldingAndUnfoldingKeepsTheSelectedTab() {
        // The selected tab is model state; only the pane set changes with width.
        for tab in TimelineModel.Tab.allCases {
            #expect(PaneLayout.panes(for: tab, isRegularWidth: true).contains(tab))
        }
    }
}
