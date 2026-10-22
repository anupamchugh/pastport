import AppIntents
import PastportKit

/// The one App Intent: opens Pastport on the locked Timeline. It reads nothing and returns no data;
/// Face ID is still asked for before anything is read. Callers: the "Open Timeline" Shortcuts action
/// and Siri/Spotlight phrases below, both listed in the App Store notes.
struct OpenTimelineIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Timeline"
    static let description = IntentDescription("Opens Pastport on your locked timeline. Nothing is read until you unlock it.")
    static let supportedModes: IntentModes = .foreground

    @MainActor func perform() async throws -> some IntentResult {
        SharedTimeline.model.openTimeline()
        return .result()
    }
}

struct PastportShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: OpenTimelineIntent(),
                    phrases: ["Open my timeline in \(.applicationName)", "Open \(.applicationName) timeline"],
                    shortTitle: "Open Timeline", systemImageName: "clock.arrow.circlepath")
    }
}
