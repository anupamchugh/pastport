import Testing
@testable import PastportKit

@Suite("Pane layout")
struct PaneLayoutTests {
    @Test func compactShowsOnePane() {
        for tab in TimelineModel.Tab.allCases {
            #expect(PaneLayout.panes(for: tab, width: 393) == [tab])
        }
        #expect(PaneLayout.panes(for: .ask, width: PaneLayout.twoPaneMinimumWidth - 1) == [.ask])
    }

    @Test func wideTimelineAndAskShareTheScreen() {
        #expect(PaneLayout.panes(for: .trail, width: 900) == [.trail, .ask])
        #expect(PaneLayout.panes(for: .ask, width: PaneLayout.twoPaneMinimumWidth) == [.trail, .ask])
    }

    @Test func wideAddAndPrivacyShareTheScreen() {
        #expect(PaneLayout.panes(for: .add, width: 1024) == [.add, .privacy])
        #expect(PaneLayout.panes(for: .privacy, width: 1024) == [.add, .privacy])
    }
}
