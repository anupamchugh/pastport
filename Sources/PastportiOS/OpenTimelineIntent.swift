import AppIntents
import Foundation
import PastportKit

/// Opens Pastport on the locked Timeline. It reads nothing and returns no data;
/// Face ID is still asked for before anything is read. Callers: the "Open Timeline" Shortcuts action
/// and Siri/Spotlight phrases below.
struct OpenTimelineIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Timeline"
    static let description = IntentDescription("Opens Pastport on your locked timeline. Nothing is read until you unlock it.")
    static let supportedModes: IntentModes = .foreground

    @MainActor func perform() async throws -> some IntentResult {
        SharedTimeline.model.openTimeline()
        return .result()
    }
}

/// Saves a research link discovered during browsing directly into Feedloom's pending reading list.
struct SaveResearchToFeedloomIntent: AppIntent {
    static let title: LocalizedStringResource = "Save Research to Feedloom"
    static let description = IntentDescription("Saves a web link discovered during research into your Feedloom (LinkVault) library.")
    static let supportedModes: IntentModes = .background

    @Parameter(title: "URL")
    var url: URL

    @Parameter(title: "Title")
    var title: String

    @Parameter(title: "Topic or Tag")
    var topic: String?

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let bridge = FeedloomBridge()
        let tags = (topic.map { [$0.lowercased()] } ?? ["pastport-research"])
        try bridge.saveToFeedloom(
            url: url.absoluteString,
            title: title,
            notes: "Saved from Pastport Intent Research",
            tags: tags
        )

        return .result(dialog: IntentDialog("Queued '\(title)' for Feedloom to import."))
    }
}

/// Hands a question from Siri or Shortcuts to Ask on the locked screen. It reads nothing and
/// returns nothing: the answer appears in the app after Face ID, never in Siri.
struct AskPastportIntent: AppIntent {
    static let title: LocalizedStringResource = "Ask Pastport"
    static let description = IntentDescription("Opens Ask with your question. Pastport answers on this device after you unlock it.")
    static let supportedModes: IntentModes = .foreground

    @Parameter(title: "Question", requestValueDialog: "What do you want to ask Pastport?")
    var question: String

    @MainActor func perform() async throws -> some IntentResult {
        SharedTimeline.model.openAsk(question: question)
        return .result()
    }
}

/// Imports a Safari export ZIP chosen in Shortcuts (for example "Find Files", newest ZIP). Face ID is asked before the
/// file is opened, only the history and the Reading List are read, and the result lives in memory until Pastport
/// locks. It returns nothing.
struct ImportSafariExportIntent: AppIntent {
    static let title: LocalizedStringResource = "Import Safari Export"
    static let description = IntentDescription("Opens Pastport and imports a Safari export you choose. Face ID is asked first. Nothing is kept after you lock Pastport.")
    static let supportedModes: IntentModes = .foreground

    @Parameter(title: "Safari export", description: "The ZIP from Safari's Export Browsing Data.", supportedContentTypes: [.zip])
    var file: IntentFile

    @MainActor func perform() async throws -> some IntentResult {
        let model = SharedTimeline.model
        model.tab = .trail
        model.importSafariExport(data: file.data)
        return .result()
    }
}

struct PastportShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: OpenTimelineIntent(),
            phrases: [
                "Open my timeline in \(.applicationName)",
                "Open \(.applicationName) timeline"
            ],
            shortTitle: "Open Timeline",
            systemImageName: "clock.arrow.circlepath"
        )
        AppShortcut(
            intent: AskPastportIntent(),
            phrases: [
                "Ask \(.applicationName)",
                "Ask \(.applicationName) a question",
                "Ask my \(.applicationName) timeline"
            ],
            shortTitle: "Ask Pastport",
            systemImageName: "bubble.left.and.text.bubble.right"
        )
        AppShortcut(
            intent: SaveResearchToFeedloomIntent(),
            phrases: [
                "Save research to Feedloom in \(.applicationName)"
            ],
            shortTitle: "Save to Feedloom",
            systemImageName: "bookmark"
        )
    }
}
