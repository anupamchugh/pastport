import PastportKit
import SwiftUI

/// One commitment in a trip — a ticket, a stay, the paperwork. Denser than a card because
/// travel comes in runs: a flight, then a room, then an arrival form, over a few days.
public struct TravelRow: View {
    let booking: Booking

    public init(booking: Booking) { self.booking = booking }

    private var icon: String {
        switch booking.kind {
        case .ticket, .itinerary: "airplane"
        case .checkout: "creditcard"
        case .confirmation: "checkmark.seal"
        }
    }

    public var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: icon).foregroundStyle(.orange).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                // The page title carries the place far more often than the URL does —
                // "Wave House - Arashiyama, Japan" needs no extraction at all.
                Text(booking.title.isEmpty ? Bookings.name(for: booking.host) : booking.title)
                    .font(.callout).lineLimit(2)
                Text(booking.time.formatted(.dateTime.month(.abbreviated).day()))
                    .font(.caption2).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.vertical, 5).padding(.horizontal, 10)
        .background(.quaternary.opacity(0.25))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .combine)
    }
}

/// One stretch of "I was trying to work something out". Shows the person's own queries
/// verbatim — the point is recognition, so paraphrasing would defeat it.
public struct ThreadCard: View {
    let thread: IntentThread
    let unlock: @MainActor () async -> Bool
    @State private var expanded = false
    @State private var revealed = false
    @State private var unlocking = false

    public init(thread: IntentThread, unlock: @escaping @MainActor () async -> Bool) {
        self.thread = thread
        self.unlock = unlock
    }

    /// One place decides how many queries show, so the button's label can't disagree
    /// with what the list actually renders.
    private var visibleQueries: Int { expanded ? thread.queries.count : 2 }

    /// A sensitive thread shows nothing — not the topic, not the count. The topic word is
    /// the disclosure, so hiding only the queries underneath it would protect nothing.
    private var locked: Bool { thread.isSensitive && !revealed }

    public var body: some View {
        if locked { lockedCard } else { openCard }
    }

    private var lockedCard: some View {
        HStack(spacing: 10) {
            Image(systemName: "lock.fill").foregroundStyle(.secondary).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("A private thread").font(.callout.weight(.semibold))
                Text("Authenticate to view").font(.caption).foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
            Spacer()
            Button(unlocking ? "Waiting…" : "Unlock") {
                unlocking = true
                Task { @MainActor in
                    revealed = await unlock()
                    unlocking = false
                }
            }
            .buttonStyle(.bordered).controlSize(.small).disabled(unlocking)
            .accessibilityHint("Asks for Touch ID, Face ID or your passcode")
        }
        .padding(10)
        .background(.quaternary.opacity(0.3))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private var openCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.teal).accessibilityHidden(true)
                Text(thread.headline).font(.callout.weight(.semibold))
                Spacer()
                // Count what the card can actually show: unique phrasings, not search events.
                Text("\(thread.queries.count) searches")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            // Queries are deduped at construction, so they're safe to identify by value.
            ForEach(thread.queries.prefix(visibleQueries), id: \.self) { q in
                Text("“\(q)”").font(.caption).foregroundStyle(.secondary)
            }
            if !thread.destinations.isEmpty {
                FlowChips(items: Array(thread.destinations.prefix(4)))
            }
            if thread.queries.count > visibleQueries || expanded {
                Button { expanded.toggle() } label: {
                    Text(expanded ? "Show less" : "Show all \(thread.queries.count) searches")
                        .font(.caption2)
                }.buttonStyle(.plain).foregroundStyle(.secondary)
            }
        }
        .padding(10)
        .background(.quaternary.opacity(0.3))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

public struct MovementCard: View {
    let leak: LocationLeak
    @State private var showReceipt = false

    public init(leak: LocationLeak) { self.leak = leak }

    public var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: "mappin.and.ellipse").foregroundStyle(.orange).accessibilityHidden(true)
                Text(leak.headline).font(.headline)
                Spacer()
            }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) { placeLine; Spacer(); mapsLink }
                VStack(alignment: .leading, spacing: 4) { placeLine; mapsLink }
            }
            Button { showReceipt.toggle() } label: {
                Text(showReceipt ? "Hide the link" : "How do we know this?").font(.caption2)
            }.buttonStyle(.plain).foregroundStyle(.secondary)
            if showReceipt {
                // The full address and the raw link live here, together: this is the
                // evidence, and it's the part you wouldn't want on screen by default.
                if let address = leak.address {
                    Text(address).font(.caption).textSelection(.enabled)
                }
                Text(leak.decodedURL).font(.caption2.monospaced()).foregroundStyle(.secondary)
                    .textSelection(.enabled).lineLimit(4)
            }
        }
        .padding(11).frame(maxWidth: .infinity, alignment: .leading)
        .background(.background, in: RoundedRectangle(cornerRadius: 9))
        .overlay(RoundedRectangle(cornerRadius: 9).stroke(.quaternary))
    }

    private var placeLine: some View {
        HStack(spacing: 8) {
            // A place, not a pair of floats — read out of the URL, never guessed.
            if let place = leak.place {
                Text(place).font(.callout).foregroundStyle(.secondary)
            } else {
                Text("\(coord(leak.lat)), \(coord(leak.lng))")
                    .font(.caption.monospaced()).foregroundStyle(.secondary)
            }
            Text(leak.mapProvider).font(.caption2.weight(.medium))
                .padding(.horizontal, 6).padding(.vertical, 1)
                .background(.orange.opacity(0.18)).foregroundStyle(.orange).clipShape(Capsule())
                .accessibilityLabel("Map link from \(leak.mapProvider)")
        }
    }

    @ViewBuilder private var mapsLink: some View {
        if let url = URL(string: "https://maps.apple.com/?ll=\(leak.lat),\(leak.lng)") {
            Link("Open in Maps", destination: url).font(.caption)
        }
    }

    private func coord(_ v: Double) -> String { String(format: "%.5f", v) }
}

/// A simple wrapping row of chips.
public struct FlowChips: View {
    let items: [String]

    public init(items: [String]) { self.items = items }

    public var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 90), spacing: 6)], alignment: .leading, spacing: 6) {
            ForEach(items, id: \.self) { s in
                Text(s).font(.caption).lineLimit(2)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(.tint.opacity(0.14)).clipShape(Capsule())
            }
        }
    }
}
