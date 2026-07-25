import Foundation

/// Fictional rows for screenshots and manual UI review.
///
/// Demo mode is opt-in (`--demo` or `PASTPORT_DEMO=1`) and never reads Safari.
public enum DemoData {
    public static let visits: [Visit] = {
        let base = Date(timeIntervalSince1970: 1_751_328_000) // 2025-06-17
        return [
            Visit(time: base, title: "Leaving Airbnb", url: "https://airbnb.example/interstitial?r=https%3A%2F%2Fmaps.example%2F%3Fq%3D18%2BRue%2BDemo%252C%2B5th%2BArrondissement%252C%2BParis%252C%2BFrance%26ll%3D48.8566%252C2.3522"),
            Visit(time: base.addingTimeInterval(-86_400), title: "Your itinerary", url: "https://flights.example/itinerary/demo-trip"),
            Visit(time: base.addingTimeInterval(-172_800), title: "Booking confirmed — Demo Stay", url: "https://stay.example/booking/confirmation"),
            Visit(time: base.addingTimeInterval(-259_200), title: "Demo arrival card", url: "https://forms.example/arrival"),
            Visit(time: base.addingTimeInterval(-345_600), title: "Paris museum hours - Search", url: "https://search.example/search?q=paris+museums"),
            Visit(time: base.addingTimeInterval(-432_000), title: "Train pass options - Search", url: "https://search.example/search?q=train+pass"),
            Visit(time: base.addingTimeInterval(-518_400), title: "Local food guide", url: "https://guide.example/paris"),
        ]
    }()
}
