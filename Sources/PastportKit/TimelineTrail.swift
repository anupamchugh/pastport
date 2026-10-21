import Foundation

/// The four iPhone trails. Separate from the Mac's `HistoryFocus`, whose research and places
/// trails need Safari history.
public enum TimelineTrail: String, CaseIterable, Identifiable, Sendable {
    case overview
    case travel
    case photos
    case privacy

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .overview: "Overview"
        case .travel: "Travel"
        case .photos: "Photos"
        case .privacy: "Privacy"
        }
    }

    /// Suggested questions shown as chips in Ask while this trail is open.
    public var askChips: [String] {
        switch self {
        case .overview: ["What does my timeline show for this window?", "What did I add?"]
        case .travel: ["Which days have the most photos?", "What bookings did I add?"]
        case .photos: ["What does my photo activity show?", "Which scene labels come up most?"]
        case .privacy: ["What was hidden in my screenshots?", "What can Pastport read on this iPhone?"]
        }
    }
}
