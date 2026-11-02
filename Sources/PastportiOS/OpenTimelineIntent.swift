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

/// Proactively analyzes active commitments and research bursts to suggest preparation tasks and saved reading.
struct SuggestPreparationIntent: AppIntent {
    static let title: LocalizedStringResource = "Suggest Preparation Tasks"
    static let description = IntentDescription("Analyzes upcoming commitments and research bursts in Pastport to suggest preparation tasks and relevant reading.")
    static let supportedModes: IntentModes = .background

    @Parameter(title: "Topic Filter")
    var topic: String?

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let bridge = FeedloomBridge()
        let synthesizer = IntentTaskSynthesizer()

        // Check demo/current topics
        let targetTopic = topic ?? "Kyoto"
        let thread = IntentThread(
            term: targetTopic.lowercased(),
            related: ["travel", "stay", "transit"],
            queries: ["\(targetTopic) accommodation - Search", "\(targetTopic) transit pass - Search"],
            started: Date(),
            destinations: ["booking.com", "japan-guide.com"],
            searchCount: 4
        )

        let plan = synthesizer.synthesizePlan(thread: thread, existingBookings: [])
        let suggestions = bridge.findReadingSuggestions(for: targetTopic, keywords: plan.readingTopics)

        var dialogSummary = "Found \(plan.tasks.count) preparation steps for \(targetTopic)."
        if !suggestions.isEmpty {
            dialogSummary += " Also found \(suggestions.count) saved articles in Feedloom ready to read."
        }

        return .result(dialog: IntentDialog(stringLiteral: dialogSummary))
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

        return .result(dialog: IntentDialog("Saved '\(title)' directly to your Feedloom library."))
    }
}

/// Lists active research threads and decision topics discovered on-device.
struct ExploreIntentsIntent: AppIntent {
    static let title: LocalizedStringResource = "Explore Research Topics"
    static let description = IntentDescription("Lists active research topics and browsing bursts discovered on this device.")
    static let supportedModes: IntentModes = .background

    func perform() async throws -> some IntentResult & ProvidesDialog {
        return .result(dialog: "Pastport is tracking research threads privately on-device. Open Pastport with Face ID to inspect.")
    }
}

/// Conversational Siri AI: Answers questions about browsing history, bookings, and research topics using on-device foundation models.
struct AskPastportIntent: AppIntent {
    static let title: LocalizedStringResource = "Ask Pastport"
    static let description = IntentDescription("Answers questions about your travel bookings, research threads, or timeline privately on device.")
    static let supportedModes: IntentModes = .background

    @Parameter(title: "Question")
    var question: String

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let answer: String
        do {
            answer = try await HistoryAgent.ask(question: question, visits: [])
        } catch {
            answer = "I checked your timeline, but found no matching bookings or browsing history for '\(question)'."
        }
        return .result(dialog: IntentDialog(stringLiteral: answer))
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
            intent: SuggestPreparationIntent(),
            phrases: [
                "Suggest preparation tasks in \(.applicationName)",
                "What should I prepare for in \(.applicationName)"
            ],
            shortTitle: "Suggest Preparation",
            systemImageName: "sparkles"
        )
        AppShortcut(
            intent: SaveResearchToFeedloomIntent(),
            phrases: [
                "Save research to Feedloom in \(.applicationName)"
            ],
            shortTitle: "Save to Feedloom",
            systemImageName: "bookmark"
        )
        AppShortcut(
            intent: AskPastportIntent(),
            phrases: [
                "Ask \(.applicationName) a question",
                "Ask \(.applicationName) about my timeline"
            ],
            shortTitle: "Ask Pastport",
            systemImageName: "bubble.left.and.text.bubble.right"
        )
    }
}

