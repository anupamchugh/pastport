import PastportKit
import SwiftUI

/// One evidence card: source label, one sentence, the facts, and a closed "How do we know this?".
public struct EvidenceCardView: View {
    let card: EvidenceCard
    @State private var expanded = false

    public init(card: EvidenceCard) { self.card = card }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 8) {
                SourceLabel(card.source.rawValue)
                Text(card.sentence)
                    .font(.system(.title3, design: .serif).weight(.semibold))
                    .foregroundStyle(Palette.ink)
                    .fixedSize(horizontal: false, vertical: true)
                if !card.details.isEmpty {
                    Text(card.details.joined(separator: " · "))
                        .font(.subheadline.monospacedDigit()).foregroundStyle(Palette.muted)
                }
                if !card.labels.isEmpty {
                    Text("Scene labels: " + card.labels.joined(separator: ", "))
                        .font(.footnote).foregroundStyle(Palette.muted)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(card.source.rawValue.capitalized), \(card.sentence), \(card.details.count) details")

            DisclosureGroup(isExpanded: $expanded) {
                Text(card.disclosure)
                    .font(.footnote).foregroundStyle(Palette.muted)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 4)
            } label: {
                Text("How do we know this?").font(.footnote.weight(.medium)).foregroundStyle(Palette.accent)
            }
            .tint(Palette.accent.light)
        }
        .paperCard()
    }
}

/// The trail chips: Overview, Travel, Photos, Privacy.
public struct TrailChips: View {
    @Binding var trail: TimelineTrail

    public init(trail: Binding<TimelineTrail>) { _trail = trail }

    public var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(TimelineTrail.allCases) { item in
                    let selected = item == trail
                    Button { trail = item } label: {
                        Text(item.title)
                            .font(.subheadline.weight(selected ? .semibold : .regular))
                            .foregroundStyle(selected ? AnyShapeStyle(Palette.onAccent) : AnyShapeStyle(Palette.ink))
                            .padding(.horizontal, 14).frame(minHeight: 44)
                            .background(selected ? AnyShapeStyle(Palette.accent) : AnyShapeStyle(Palette.card2), in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
        }
    }
}

/// The unlocked iPhone timeline: window chips, trail chips, then the open trail's cards.
public struct TrailTimelineView: View {
    @Bindable var model: TimelineModel

    public init(model: TimelineModel) { self.model = model }

    private var emptyLine: String {
        switch model.trail {
        case .privacy: "Nothing to check yet. Add a screenshot and Pastport shows what it hid."
        case .travel: "No multi-day photo bursts or bookings in this window. Add a screenshot of a ticket to see it here."
        default: "Nothing to show yet. Allow read-only photo access, or add a screenshot of a booking."
        }
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                WindowChips(days: $model.days)
                TrailChips(trail: $model.trail)
                Text(model.photoStatus).font(.footnote).foregroundStyle(Palette.muted)
                let cards = model.evidenceCards
                if cards.isEmpty {
                    Text(emptyLine).font(.callout).foregroundStyle(Palette.muted).paperCard()
                } else {
                    ForEach(cards) { EvidenceCardView(card: $0) }
                }
                if model.trail == .overview || model.trail == .photos {
                    Text(TimelineModel.photoCopy).font(.caption).foregroundStyle(Palette.muted)
                }
            }
            .padding(16)
            .frame(maxWidth: 640, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(Palette.background)
    }
}

#if DEBUG
@MainActor private func demoPhone() -> TimelineModel {
    let model = TimelineModel(history: nil, days: 30)
    model.demoMode = true
    model.start()
    return model
}

#Preview("Timeline, Overview") {
    TrailTimelineView(model: demoPhone())
}

#Preview("Timeline, Photos, dark") {
    let model = demoPhone()
    model.trail = .photos
    return TrailTimelineView(model: model).preferredColorScheme(.dark)
}
#endif
