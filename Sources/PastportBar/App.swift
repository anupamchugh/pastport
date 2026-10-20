import AppKit
import PastportKit
import PastportMac
import SwiftUI

/// Shows a normal window + Dock icon so the app is visible even on notch Macs
/// where the menu-bar icon can hide behind the notch.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
}

@main
struct PastportBarApp: App {
    @State private var model: TimelineModel
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate

    init() {
        let model = Self.makeModel()
        _model = State(initialValue: model)
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        model.demoMode = arguments.contains("--demo") || ProcessInfo.processInfo.environment["PASTPORT_DEMO"] == "1"
        if arguments.contains("--ask") { model.openAskForScreenshots() }
        if arguments.contains("--ask-empty") { model.start(); model.tab = .ask }
        #endif
        // Screen lock clears cached history, photo activity and answers.
        ScreenLock.onLock { model.lockAndClear() }
    }

    var body: some Scene {
        // A real window — always visible, notch-proof.
        Window("Pastport", id: "main") {
            BarView(m: model)
                .frame(minWidth: 480, minHeight: 560)
                .preferredColorScheme(Self.screenshotScheme)
        }
        .defaultSize(width: 520, height: 640)

        // Plus the menu-bar item.
        MenuBarExtra("Pastport", systemImage: "clock.arrow.circlepath") {
            BarView(m: model)
                .frame(width: 520, height: 620)
        }
        .menuBarExtraStyle(.window)
    }

    /// Debug builds only: force light or dark for screenshots.
    static var screenshotScheme: ColorScheme? {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("--light") { return .light }
        if arguments.contains("--dark") { return .dark }
        #endif
        return nil
    }

    @MainActor static func makeModel() -> TimelineModel {
        TimelineModel(
            history: SafariHistorySource(),
            localModels: LocalModels(
                list: { (try? await Ollama.listModels()) ?? [] },
                generate: { model, prompt in try await Ollama.generate(model: model, prompt: prompt) }
            )
        )
    }
}
