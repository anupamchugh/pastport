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

/// Tabs on a narrow width; timeline and Ask side by side when there is room.
struct RootView: View {
    @Bindable var model: TimelineModel
    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        if sizeClass == .regular {
            HStack(spacing: 0) {
                TimelineScreen(model: model).frame(minWidth: 320, idealWidth: 420, maxWidth: 480)
                Divider()
                AskScreen(model: model)
            }
        } else {
            TabView(selection: $model.tab) {
                Tab("Timeline", systemImage: "clock.arrow.circlepath", value: TimelineModel.Tab.trail) {
                    TimelineScreen(model: model)
                }
                Tab("Ask", systemImage: "bubble.left.and.text.bubble.right", value: TimelineModel.Tab.ask) {
                    AskScreen(model: model)
                }
                Tab("Add", systemImage: "plus.viewfinder", value: TimelineModel.Tab.add) {
                    AddScreen(model: model)
                }
                Tab("Privacy", systemImage: "hand.raised", value: TimelineModel.Tab.privacy) {
                    PrivacyScreen(model: model)
                }
            }
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
