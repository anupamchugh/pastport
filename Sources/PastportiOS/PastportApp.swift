import PastportKit
import PastportUI
import SwiftUI

@main
struct PastportApp: App {
    @State private var model = TimelineModel(history: nil, days: 30)
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView(model: model)
                .onAppear {
                    #if DEBUG
                    // Fictional data for development screenshots. Debug builds only.
                    model.demoMode = ProcessInfo.processInfo.arguments.contains("--demo")
                    #endif
                    model.start()
                    #if DEBUG
                    if ProcessInfo.processInfo.arguments.contains("--ask") { model.openAskForScreenshots() }
                    if ProcessInfo.processInfo.arguments.contains("--ask-empty") { model.tab = .ask }
                    #endif
                }
        }
        .onChange(of: scenePhase) { _, phase in
            // Leaving the app clears everything that was read, like screen lock on the Mac.
            if phase == .background { model.lockAndClear() }
        }
    }
}

/// One tab at compact width; at regular width `PaneLayout` pairs Timeline with Ask and Add with
/// Privacy. The selected tab lives in the model, so folding and unfolding keeps it. The tab bar is
/// the system's (`sidebarAdaptable`), which the system moves aside on the Duo's outer display.
struct RootView: View {
    @Bindable var model: TimelineModel
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    var body: some View {
        TabView(selection: $model.tab) {
            ForEach(TimelineModel.Tab.allCases) { tab in
                Tab(tab.title, systemImage: tab.symbol, value: tab) {
                    Panes(model: model, panes: PaneLayout.panes(for: tab, isRegularWidth: horizontalSizeClass == .regular))
                }
            }
        }
        .tabViewStyle(.sidebarAdaptable)
    }
}

/// One pane, or two side by side. The pair uses the system arrangement view where it exists
/// (iOS 27.1), which keeps both panes clear of the Duo's fold; earlier systems get a plain split.
private struct Panes: View {
    var model: TimelineModel
    var panes: [TimelineModel.Tab]

    var body: some View {
        if panes.count == 2 {
            if #available(iOS 27.1, *) {
                ArrangementView {
                    pane(panes[0])
                } secondary: {
                    pane(panes[1])
                }
                .arrangementViewStyle(.split.axes(.horizontal))
            } else {
                HStack(spacing: 0) {
                    pane(panes[0]).frame(maxWidth: .infinity)
                    Divider()
                    pane(panes[1]).frame(maxWidth: .infinity)
                }
            }
        } else {
            pane(panes[0])
        }
    }

    @ViewBuilder private func pane(_ tab: TimelineModel.Tab) -> some View {
        switch tab {
        case .trail: TimelineScreen(model: model)
        case .ask: AskScreen(model: model)
        case .add: AddScreen(model: model)
        case .privacy: PrivacyScreen(model: model)
        }
    }
}

private extension TimelineModel.Tab {
    var title: String {
        switch self {
        case .trail: "Timeline"
        case .ask: "Ask"
        case .add: "Add"
        case .privacy: "Privacy"
        }
    }

    var symbol: String {
        switch self {
        case .trail: "clock.arrow.circlepath"
        case .ask: "bubble.left.and.text.bubble.right"
        case .add: "plus.viewfinder"
        case .privacy: "hand.raised"
        }
    }
}

struct TimelineScreen: View {
    @Bindable var model: TimelineModel

    var body: some View {
        NavigationStack {
            Group {
                if model.isLocked {
                    LockedTimelineView(model: model)
                } else {
                    VStack(spacing: 0) {
                        SessionStatus(model: model).padding(.horizontal, 16).padding(.top, 4)
                        TrailTimelineView(model: model)
                    }
                }
            }
            .id(model.contentID)
            .navigationTitle(model.isLocked ? "" : "Timeline")
            .toolbar {
                if !model.isLocked {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Lock and clear", systemImage: "lock") { model.lockAndClear() }
                            .disabled(model.busy)
                    }
                }
            }
        }
    }
}

struct AskScreen: View {
    @Bindable var model: TimelineModel

    var body: some View {
        NavigationStack {
            Group {
                if model.assistantSource == .connected {
                    ScrollView { ConnectedAssistantView(model: model.connectedAssistant) }
                } else {
                    EvidenceAskView(model: model)
                }
            }
            .id(model.contentID)
            .navigationTitle("Ask")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    AnswerSourceMenu(model: model).labelStyle(.iconOnly)
                }
            }
        }
    }
}
