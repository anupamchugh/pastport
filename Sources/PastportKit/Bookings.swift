import Foundation

/// A moment you *committed* to something — a confirmation page, an itinerary, a receipt.
///
/// This is the opposite shape to `IntentThread`. Research is a burst: many searches, tight
/// window, which is exactly what a concentration filter is built to find. A booking is one
/// or two visits to a transactional page and then silence — invisible to that filter by
/// design. Two detectors, because they are two different things.
public struct Booking: Identifiable, Finding {
    public let id = UUID()
    public let time: Date
    public let host: String
    public let kind: Kind
    public let title: String
    public let url: String        // query-stripped; the receipt is the path, not the params

    public enum Kind: String {
        case confirmation   // "your booking is confirmed"
        case itinerary      // a trip/booking you can go back and look at
        case checkout       // money about to move
        case ticket         // a boarding pass, PNR, e-ticket
    }

    public init(time: Date, host: String, kind: Kind, title: String, url: String) {
        self.time = time
        self.host = host
        self.kind = kind
        self.title = title
        self.url = url
    }

    public var headline: String {
        let when = time.formatted(.dateTime.year().month(.abbreviated).day())
        return "\(when): \(kind.rawValue) on \(Bookings.name(for: host))"
    }

    /// Whether this commitment was about going somewhere. Flights, stays and the paperwork
    /// around them are one story — you don't think of "the flight" and "the hotel" as
    /// separate events, you think of the trip.
    ///
    /// Derived from what a page IS, never from who runs it: an itinerary or a ticket is
    /// travel by definition, and the rest is decided by ordinary travel vocabulary. A
    /// software subscription checkout has none of these words; a guesthouse confirmation
    /// has several.
    public var isTravel: Bool {
        // An itinerary is travel by definition. A *ticket* is not — cinemas and events
        // issue those too, and real history proved it: a cinema e-ticket was landing in
        // the travel list. Tickets have to earn it through vocabulary like anything else.
        if kind == .itinerary { return true }
        let words = ["flight", "hotel", "stay", "trip", "room", "guest", "hostel",
                     "arrival", "departure", "boarding", "checkin", "airport", "airline",
                     "travel", "tour", "visa", "reservation", "booked", "booking"]
        return Bookings.containsWord(anyOf: words, in: title + " " + url)
    }

    public var key: String {
        "\(host)|\(kind.rawValue)|\(time.formatted(.iso8601.year().month().day()))"
    }

    public var notificationBody: String {
        title.isEmpty ? url : title
    }
}

/// Deterministic detection of transactions. Like `Trackers`, this matches **URL and title
/// shape**, never a list of companies — a booking confirmation looks the same on a site
/// nobody has heard of. Nothing here needs updating when a new travel site appears.
public enum Bookings {

    /// Path fragments that only appear once a transaction is underway or done. Deliberately
    /// specific: `/book` alone would match every "book a demo" marketing page, and `/order`
    /// needs a boundary or it matches "border", "reorder", "ordering".
    static let pathSignals: [(String, Booking.Kind)] = [
        ("/confirmation", .confirmation), ("/confirmed", .confirmation),
        ("/booking-confirm", .confirmation), ("/reservation", .confirmation),
        ("/itinerary", .itinerary), ("/mytrips", .itinerary), ("/my-trips", .itinerary),
        ("/trips/", .itinerary), ("/bookings/", .itinerary), ("/reservations/", .itinerary),
        ("/checkout", .checkout), ("/payment", .checkout), ("/receipt", .checkout),
        ("/invoice", .checkout),
        ("/boardingpass", .ticket), ("/boarding-pass", .ticket), ("/eticket", .ticket),
        ("/e-ticket", .ticket), ("/pnr", .ticket),
    ]

    /// Title phrasings that survive across languages of commerce. Checked lowercased.
    static let titleSignals: [(String, Booking.Kind)] = [
        ("booking confirmed", .confirmation), ("booking confirmation", .confirmation),
        ("reservation confirmed", .confirmation), ("your booking", .confirmation),
        ("your trip", .itinerary), ("your itinerary", .itinerary), ("my trips", .itinerary),
        ("order confirmation", .checkout), ("payment successful", .checkout),
        ("boarding pass", .ticket), ("e-ticket", .ticket),
    ]

    /// Query keys that only exist once a booking has an identity.
    static let paramSignals = ["booking_id", "bookingid", "reservation_id", "itinerary_id", "pnr="]

    /// Whole-word matching. Plain `contains` reported a video called "…and Your Tripod
    /// Broke" as an itinerary, because "your trip" is a substring of "your tripod" — the
    /// kind of bug that only shows up against a real history.
    static func containsWord(anyOf words: [String], in text: String) -> Bool {
        let haystack = text.lowercased()
        return words.contains { word in
            var searchStart = haystack.startIndex
            while let range = haystack.range(of: word, range: searchStart..<haystack.endIndex) {
                let beforeOK = range.lowerBound == haystack.startIndex
                    || !haystack[haystack.index(before: range.lowerBound)].isLetter
                // Allow a plural: whole-word matching alone made "hotels" stop matching
                // "hotel", which dropped a real accommodation confirmation.
                var end = range.upperBound
                if end < haystack.endIndex, haystack[end] == "s" {
                    end = haystack.index(after: end)
                }
                let afterOK = end == haystack.endIndex || !haystack[end].isLetter
                if beforeOK && afterOK { return true }
                searchStart = range.upperBound
            }
            return false
        }
    }

    /// Classify a single visit, or nil when it isn't transactional.
    public static func classify(title: String, url: String) -> Booking.Kind? {
        let u = url.lowercased()
        let t = title.lowercased()

        // Path is the strongest signal: it reflects where the site put you, not what it
        // chose to call the page.
        for (fragment, kind) in pathSignals where u.contains(fragment) { return kind }
        // Whole-word, or "your trip" matches "Your Tripod" — which it did, on real data.
        for (phrase, kind) in titleSignals where Bookings.containsWord(anyOf: [phrase], in: t) {
            return kind
        }
        for key in paramSignals where u.contains(key) { return .confirmation }
        return nil
    }

    public static func scan(from visits: [Visit]) -> [Booking] {
        var seen = Set<String>()
        var out: [Booking] = []

        for visit in visits {
            guard let kind = classify(title: visit.title, url: visit.url) else { continue }
            let host = visit.host
            guard !host.isEmpty else { continue }
            // A confirmation page reopened five times is one booking. Collapse on the day
            // plus the page, so a genuine second booking on the same site still counts.
            let day = visit.time.formatted(.iso8601.year().month().day())
            guard seen.insert("\(day)|\(host)|\(kind.rawValue)").inserted else { continue }
            out.append(Booking(time: visit.time, host: host, kind: kind,
                               title: visit.title, url: visit.cleanURL))
        }
        return out.sorted { $0.time > $1.time }
    }

    /// `"www.example.co.uk"` → `"Example"`. Derived at runtime, exactly like
    /// `Movements.appName(for:)` — no brand ever appears in this file.
    public static func name(for host: String) -> String {
        var labels = host.split(separator: ".").map(String.init)
        while let first = labels.first, ["www", "m", "secure", "book", "app"].contains(first),
              labels.count > 2 {
            labels.removeFirst()
        }
        let core = labels.first ?? host
        return core.prefix(1).uppercased() + core.dropFirst()
    }

    /// Digest lines, newest first.
    public static func digestLines(_ bookings: [Booking], limit: Int = 8) -> [String] {
        bookings.prefix(limit).map(\.headline)
    }
}
