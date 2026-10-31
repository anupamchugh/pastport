import AppIntents
import Foundation

/// AppEntity exposing an on-device browsing intent thread to Siri, Spotlight, and Shortcuts.
public struct PastportIntentEntity: AppEntity, Identifiable, Sendable {
    public static let defaultQuery = PastportIntentEntityQuery()
    public static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Research Intent")

    public let id: String
    public let topic: String
    public let headline: String
    public let queriesSummary: String
    public let destinationsSummary: String
    public let searchCount: Int

    public init(id: String, topic: String, headline: String, queriesSummary: String, destinationsSummary: String, searchCount: Int) {
        self.id = id
        self.topic = topic
        self.headline = headline
        self.queriesSummary = queriesSummary
        self.destinationsSummary = destinationsSummary
        self.searchCount = searchCount
    }

    public init(thread: IntentThread) {
        self.id = thread.key
        self.topic = thread.term.capitalized
        self.headline = thread.headline
        self.queriesSummary = thread.queries.prefix(3).joined(separator: ", ")
        self.destinationsSummary = thread.destinations.prefix(3).joined(separator: ", ")
        self.searchCount = thread.searchCount
    }

    public var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: "\(topic)",
            subtitle: "\(headline)"
        )
    }
}

/// Query provider for PastportIntentEntity.
public struct PastportIntentEntityQuery: EntityQuery, Sendable {
    public init() {}

    public func entities(for identifiers: [String]) async throws -> [PastportIntentEntity] {
        return []
    }

    public func suggestedEntities() async throws -> [PastportIntentEntity] {
        return []
    }
}

/// AppEntity exposing a timeline booking commitment to Siri, Spotlight, and Shortcuts.
public struct PastportBookingEntity: AppEntity, Identifiable, Sendable {
    public static let defaultQuery = PastportBookingEntityQuery()
    public static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Timeline Booking")

    public let id: String
    public let title: String
    public let host: String
    public let kindName: String
    public let isTravel: Bool
    public let url: String

    public init(id: String, title: String, host: String, kindName: String, isTravel: Bool, url: String) {
        self.id = id
        self.title = title
        self.host = host
        self.kindName = kindName
        self.isTravel = isTravel
        self.url = url
    }

    public init(booking: Booking) {
        self.id = booking.key
        self.title = booking.title
        self.host = booking.host
        self.kindName = booking.kind.rawValue
        self.isTravel = booking.isTravel
        self.url = booking.url
    }

    public var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: "\(title)",
            subtitle: "\(kindName.capitalized) on \(host)"
        )
    }
}

/// Query provider for PastportBookingEntity.
public struct PastportBookingEntityQuery: EntityQuery, Sendable {
    public init() {}

    public func entities(for identifiers: [String]) async throws -> [PastportBookingEntity] {
        return []
    }

    public func suggestedEntities() async throws -> [PastportBookingEntity] {
        return []
    }
}
