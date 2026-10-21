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

/// One tab on a narrow width; on a wide one, `PaneLayout` pairs Timeline with Ask and Add
/// with Privacy, with the tab rail on the trailing edge. Width comes from the container.
struct RootView: View {
    @Bindable var model: TimelineModel
    @State private var width: Double = 0

    var body: some View {
        let panes = PaneLayout.panes(for: model.tab, width: width)
        Group {
            if panes.count == 2 {
                HStack(spacing: 0) {
                    pane(panes[0]).frame(maxWidth: .infinity)
                    Divider()
                    pane(panes[1]).frame(maxWidth: .infinity)
                    Divider()
                    TabRail(tab: $model.tab)
                }
            } else {
                TabView(selection: $model.tab) {
                    ForEach(TimelineModel.Tab.allCases) { tab in
                        Tab(tab.title, systemImage: tab.symbol, value: tab) { pane(tab) }
                    }
                }
            }
        }
        .onGeometryChange(for: Double.self) { Double($0.size.width) } action: { width = $0 }
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

/// The wide-layout tab rail: icon above a short label, 62 points wide.
private struct TabRail: View {
    @Binding var tab: TimelineModel.Tab

    var body: some View {
        VStack(spacing: 6) {
            ForEach(TimelineModel.Tab.allCases) { item in
                Button { tab = item } label: {
                    VStack(spacing: 3) {
                        Image(systemName: item.symbol).font(.title3)
                        Text(item.title).font(.caption2)
                    }
                    .frame(width: 62, height: 56)
                    .foregroundStyle(item == tab ? Color.accentColor : .secondary)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(item == tab ? .isSelected : [])
            }
            Spacer()
        }
        .padding(.top, 12)
        .frame(width: 62)
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
