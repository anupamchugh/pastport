import Foundation

/// The tools a person can switch on in Connected tools. Each one is off at every launch and asks before every use.
public enum ConnectedTool: String, CaseIterable, Codable, Hashable, Sendable, Identifiable {
    case weather
    case web
    case contacts
    case calendar
    case reminders
    case location
    case health
    case music
    case webMetadata

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .weather: String(localized: "Weather")
        case .web: String(localized: "Web Search")
        case .contacts: String(localized: "Contacts")
        case .calendar: String(localized: "Calendar")
        case .reminders: String(localized: "Reminders")
        case .location: String(localized: "Location")
        case .health: String(localized: "Health")
        case .music: String(localized: "Music")
        case .webMetadata: String(localized: "Web Metadata")
        }
    }

    public var systemImage: String {
        switch self {
        case .weather: "cloud.sun"
        case .web: "globe"
        case .contacts: "person.crop.circle"
        case .calendar: "calendar"
        case .reminders: "checklist"
        case .location: "location"
        case .health: "heart.text.square"
        case .music: "music.note"
        case .webMetadata: "link"
        }
    }
}
