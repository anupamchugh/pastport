import Foundation

/// A moment where a coordinate *and* a timestamp were sitting in a Safari URL — usually
/// because an app (Airbnb, a hotel site, a listing) bounced an outbound tap through a
/// "You're leaving…" interstitial to a map, embedding exact GPS in the redirect. Direct
/// map look-ups count too. This is the "your iPhone just left an Airbnb" signal: where you
/// were headed, and when, in the clear.
public struct LocationLeak: Identifiable, Finding {
    public let id = UUID()
    public let time: Date
    public let fromApp: String?     // the app you left, e.g. "Airbnb" — nil for a direct map look-up
    public let fromHost: String
    public let lat: Double
    public let lng: Double
    public let mapProvider: String  // "Google Maps" / "Apple Maps" / "a map"
    public let decodedURL: String   // the un-percent-encoded URL, for --raw inspection

    public init(time: Date, fromApp: String?, fromHost: String,
                lat: Double, lng: Double, mapProvider: String, decodedURL: String) {
        self.time = time
        self.fromApp = fromApp
        self.fromHost = fromHost
        self.lat = lat
        self.lng = lng
        self.mapProvider = mapProvider
        self.decodedURL = decodedURL
    }

    /// Stable identity for "have I already told you about this?" — app + rounded coordinate.
    public var key: String {
        "\(fromApp ?? fromHost)|\(String(format: "%.4f", lat)),\(String(format: "%.4f", lng))"
    }

    /// A deterministic one-line headline — the phrase a notification shows, no model needed.
    public var headline: String {
        let when = time.formatted(.dateTime.weekday(.wide).hour().minute())
        if let app = fromApp { return "Your iPhone left \(app) on \(when)" }
        return "You looked up a place on \(when)"
    }

    /// The address the URL is carrying, if it carries one. No geocoder, no network — map
    /// links put the destination in a query parameter, so the name leaks exactly the way
    /// the coordinate does. This is why the card can say a place without guessing one:
    /// nothing here is inferred, it is read.
    public var address: String? { Movements.address(in: decodedURL) }

    /// The part of that address safe to put on screen by default: locality and city, with
    /// the flat number, street, postcode and country dropped. The full string is a doorstep
    /// — it belongs behind the reveal, not in a card someone can read over your shoulder.
    public var place: String? { Movements.coarsen(address) }

    public var notificationBody: String {
        "\(Movements.coord(lat)),\(Movements.coord(lng)) · \(mapProvider)"
    }
}

/// Deterministic extraction of location leaks from history. No model, nothing leaves the Mac —
/// it just decodes what is literally sitting in the URLs.
public enum Movements {
    public static func scan(from visits: [Visit]) -> [LocationLeak] {
        var seen = Set<String>()
        var out: [LocationLeak] = []
        for visit in visits {
            let decoded = deepDecode(visit.url)
            guard let (lat, lng) = firstCoordinate(in: decoded) else { continue }

            let host = visit.host
            let isMapHost = host.contains("google") || host.contains("maps") || host.contains("apple.com")
            let leftApp = Trackers.classify(title: visit.title, url: visit.url).map {
                $0 == .interstitial || $0 == .redirect
            } ?? false
            let fromApp = (leftApp && !isMapHost) ? appName(for: host) : nil

            // Dedupe on the coordinate + app so a page reopened many times counts once.
            let key = "\(fromApp ?? host)|\(String(format: "%.4f", lat)),\(String(format: "%.4f", lng))"
            guard seen.insert(key).inserted else { continue }

            out.append(LocationLeak(
                time: visit.time,
                fromApp: fromApp,
                fromHost: host,
                lat: lat,
                lng: lng,
                mapProvider: mapProvider(in: decoded),
                decodedURL: decoded
            ))
        }
        return out.sorted { $0.time > $1.time }
    }

    /// Prompt for the on-device model to narrate the leaks in the second person. The optional
    /// `instruction` lets the person steer the voice/focus ("be blunt", "just Airbnb").
    public static func narrationPrompt(leaks: [LocationLeak], instruction: String?, days: Int) -> String {
        let lines = leaks.prefix(20).map { leak -> String in
            let when = leak.time.formatted(.dateTime.weekday(.wide).hour().minute())
            let src = leak.fromApp.map { "left \($0)" } ?? "opened \(leak.mapProvider)"
            return "\(when): \(src) → pin at \(coord(leak.lat)),\(coord(leak.lng)) [\(leak.mapProvider), via \(leak.fromHost)]"
        }.joined(separator: "\n")

        let steer = instruction.map { "\nThe person asked you to: \($0)\n" } ?? ""
        return """
        You read a person's own Safari history, on-device. Below are location leaks found
        deterministically: moments where an exact coordinate AND a timestamp were sitting in a
        URL. Often an app — a listing, hotel, or travel site — routed an outbound tap through a
        "You're leaving…" interstitial to a map, embedding the GPS of where the person was headed.

        Narrate what this reveals, in the second person (e.g. "Your iPhone left <the app> on…",
        naming the actual app from the data).
        For each notable leak, state plainly WHERE (the coordinate) and WHEN, and note that the
        source app could see the same. Invent nothing that is not in the data; if you infer,
        say you are inferring. Keep it to a few tight lines — this is Find My for everything.
        \(steer)
        LEAKS (last \(days) days):
        \(lines)
        """
    }

    // MARK: - helpers

    static func coord(_ v: Double) -> String { String(format: "%.5f", v) }

    /// Percent-decode repeatedly (Airbnb double-encodes the redirect target).
    static func deepDecode(_ s: String) -> String {
        var current = s
        for _ in 0..<3 {
            guard let next = current.removingPercentEncoding, next != current else { break }
            current = next
        }
        return current
    }

    /// First plausible "lat,lng" pair. Requires ≥4 decimal places so version/zoom numbers
    /// don't masquerade as coordinates, and bounds-checks lat/lng.
    static func firstCoordinate(in text: String) -> (Double, Double)? {
        guard let re = try? NSRegularExpression(
            pattern: #"@?(-?\d{1,3}\.\d{4,}),\s*(-?\d{1,3}\.\d{4,})"#
        ) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        for match in re.matches(in: text, range: range) {
            guard let latR = Range(match.range(at: 1), in: text),
                  let lngR = Range(match.range(at: 2), in: text),
                  let lat = Double(text[latR]), let lng = Double(text[lngR]),
                  abs(lat) <= 90, abs(lng) <= 180,
                  !(lat == 0 && lng == 0) else { continue }
            return (lat, lng)
        }
        return nil
    }

    /// Query keys map links use for "the place I mean". Wire format, not brands.
    static let placeKeys = ["q=", "daddr=", "destination=", "address=", "saddr="]

    /// Pull the destination out of a decoded map URL.
    static func address(in decoded: String) -> String? {
        for key in placeKeys {
            guard let start = decoded.range(of: key) else { continue }
            let rest = decoded[start.upperBound...]
            let value = rest.prefix { $0 != "&" }
            // Map links encode spaces as "+"; a bare coordinate isn't an address.
            let text = value.replacingOccurrences(of: "+", with: " ")
                .trimmingCharacters(in: .whitespaces)
            guard text.count > 8, text.contains(","),
                  text.rangeOfCharacter(from: .letters) != nil else { continue }
            return text
        }
        return nil
    }

    /// "12, Rue Lepic, Montmartre, 18th arrondissement, Paris, Ile-de-France
    /// 75018, France" → "Montmartre, Paris". Drops the doorstep and the country.
    static func coarsen(_ address: String?) -> String? {
        guard let address else { return nil }
        var parts = address.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { part in
                guard !part.isEmpty else { return false }
                // Drop a bare house number, and anything carrying a postcode.
                if part.allSatisfy({ $0.isNumber }) { return false }
                if part.contains(where: \.isNumber) && part.split(separator: " ").contains(where: {
                    $0.count >= 5 && $0.allSatisfy(\.isNumber)
                }) { return false }
                return true
            }
        if parts.count > 2 { parts.removeLast() }          // country
        guard !parts.isEmpty else { return nil }
        return parts.suffix(2).joined(separator: ", ")
    }

    static func mapProvider(in text: String) -> String {
        let t = text.lowercased()
        if t.contains("google.com/maps") || t.contains("maps.google") || t.contains("goo.gl/maps") { return "Google Maps" }
        if t.contains("maps.apple") { return "Apple Maps" }
        if t.contains("openstreetmap") { return "OpenStreetMap" }
        return "a map"
    }

    /// "www.airbnb.com" → "Airbnb"; drops common subdomains first.
    static func appName(for host: String) -> String {
        var labels = host.split(separator: ".").map(String.init)
        while let first = labels.first, ["www", "m", "l", "mobile", "en"].contains(first), labels.count > 2 {
            labels.removeFirst()
        }
        let core = labels.first ?? host
        return core.prefix(1).uppercased() + core.dropFirst()
    }
}
