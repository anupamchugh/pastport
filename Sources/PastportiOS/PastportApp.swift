import PastportKit
import PastportUI
import SwiftUI

@main
struct PastportApp: App {
    @State private var model = TimelineModel(history: nil)
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
            }
        }
    }
}

struct TimelineScreen: View {
    @Bindable var model: TimelineModel

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    SessionStatus(model: model)
                    SafariStaysOnMac()
                    PhotoActivitySection(model: model)
                    Divider()
                    ScreenshotsSection(model: model)
                }
                .padding()
                .id(model.contentID)
            }
            .navigationTitle("Timeline")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        WindowPicker(days: $model.days)
                    } label: {
                        Label("Window: \(model.windowTitle)", systemImage: "calendar")
                    }
                    .disabled(model.busy)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Lock & clear", systemImage: "lock.fill") { model.lockAndClear() }
                }
            }
        }
    }
}

/// Says plainly why there is no browsing history here.
struct SafariStaysOnMac: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Safari history stays on your Mac", systemImage: "safari")
                .font(.headline)
            Text("iOS doesn't let apps read Safari history, so Pastport on iPhone and iPad builds your timeline from photo activity and screenshots you add. Pastport for Mac reads Safari history on your Mac only.")
                .font(.callout).foregroundStyle(.secondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 10))
        .accessibilityElement(children: .combine)
    }
}

struct AskScreen: View {
    let model: TimelineModel

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                AssistantSourcePicker(model: model).padding(.horizontal).padding(.vertical, 6)
                if model.assistantSource == .connected {
                    ScrollView { ConnectedAssistantView(model: model.connectedAssistant) }
                } else {
                    EvidenceAskView(model: model)
                }
            }
            .id(model.contentID)
            .navigationTitle("Ask")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
