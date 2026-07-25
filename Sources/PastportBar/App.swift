import AppKit
import SwiftUI

/// Shows a normal window + Dock icon so the app is visible even on notch Macs
/// where the menu-bar icon can hide behind the notch. Set `.accessory` for a
/// pure menu-bar utility once you no longer need the window.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
}

@main
struct PastportBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate

    var body: some Scene {
        // A real window — always visible, notch-proof.
        Window("Pastport", id: "main") {
            BarView()
                .frame(minWidth: 480, minHeight: 560)
        }
        .defaultSize(width: 520, height: 640)

        // Plus the menu-bar item.
        MenuBarExtra("Pastport", systemImage: "clock.arrow.circlepath") {
            BarView()
                .frame(width: 520, height: 620)
        }
        .menuBarExtraStyle(.window)
    }
}
