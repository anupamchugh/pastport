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

    @Test func regularWidthOffersOneTabPerPair() {
        #expect(PaneLayout.tabs(isRegularWidth: false) == TimelineModel.Tab.allCases)
        #expect(PaneLayout.tabs(isRegularWidth: true) == [.trail, .add])
    }

    @Test func regularWidthHighlightsTheTabOfTheSelectedPair() {
        #expect(PaneLayout.tab(for: .ask, isRegularWidth: true) == .trail)
        #expect(PaneLayout.tab(for: .privacy, isRegularWidth: true) == .add)
        #expect(PaneLayout.tab(for: .ask, isRegularWidth: false) == .ask)
    }

    @Test func choosingTheVisiblePairKeepsTheSelectedTab() {
        // Folding and unfolding must not move the person off Ask or Privacy.
        #expect(PaneLayout.selecting(.trail, current: .ask, isRegularWidth: true) == .ask)
        #expect(PaneLayout.selecting(.add, current: .privacy, isRegularWidth: true) == .privacy)
        #expect(PaneLayout.selecting(.add, current: .ask, isRegularWidth: true) == .add)
        #expect(PaneLayout.selecting(.trail, current: .ask, isRegularWidth: false) == .trail)
    }
}
