import PastportKit
import SwiftUI

/// First run: one sentence about what Pastport is and one action.
public struct WelcomeView: View {
    let model: TimelineModel

    public init(model: TimelineModel) { self.model = model }

    private var sentence: LocalizedStringKey {
        model.canReadHistory
            ? "Find the trips, bookings and places hiding in your Safari history, privately on your Mac."
            : "Turn your photos and screenshots into a private timeline, then ask it questions."
    }

    private var action: LocalizedStringKey { model.canReadHistory ? "Read my history" : "Read my photos" }

    private var footnote: LocalizedStringKey {
        model.canReadHistory
            ? "Read on this Mac and never uploaded. Touch ID keeps it closed until you say so."
            : "Read on this iPhone and never uploaded. Screenshots are used only when you add them."
    }

    public var body: some View {
        VStack(spacing: 18) {
            Spacer(minLength: 24)
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 44, weight: .semibold))
                .foregroundStyle(.tint)
                .accessibilityHidden(true)
            Text("Pastport").font(.largeTitle.bold())
            Text(sentence)
                .font(.title3).multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 420)
            Button {
                if model.canReadHistory { model.loadTrail() } else { model.readPhotos() }
            } label: {
                HStack(spacing: 8) {
                    if model.busy { ProgressView().controlSize(.small) }
                    Text(action)
                }.frame(minWidth: 180)
            }
            .buttonStyle(.borderedProminent).controlSize(.large)
            .disabled(model.busy)
            Text(footnote)
                .font(.footnote).multilineTextAlignment(.center)
                .foregroundStyle(.secondary).frame(maxWidth: 360)
            if let note = model.attentionStatus, !model.busy {
                Text(note).font(.footnote).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center).frame(maxWidth: 360)
            }
            if !model.canReadHistory {
                // The screenshot route is useful before any photo is read.
                ScreenshotAdder(model: model)
            }
            Spacer(minLength: 24)
        }
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity)
    }
}

/// What was found, as a few plain cards. Tapping one shows the evidence behind it.
public struct HomeView: View {
    let model: TimelineModel
    @State private var detail: HistoryFocus?

    public init(model: TimelineModel) { self.model = model }

    public var body: some View {
        if !model.hasContent {
            ScrollView { WelcomeView(model: model).frame(minHeight: 460) }
        } else if model.historyLoaded {
            if let detail {
                FindingDetail(model: model, focus: detail) { self.detail = nil }
            } else {
                ScrollView { findings.padding(16) }
            }
        } else {
            ScrollView { timeline.padding(16) }.contentMargins(.bottom, 24, for: .scrollContent)
        }
    }

    // MARK: Mac: findings from Safari history

    private var findings: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("What I found").font(.title2.bold())
                Spacer()
                Button("Refresh", systemImage: "arrow.clockwise") { model.loadTrail() }
                    .labelStyle(.iconOnly).buttonStyle(.borderless).disabled(model.busy)
                    .help("Read your history again")
            }
            ForEach(model.focusCards) { card in
                Button { detail = card.focus } label: { FindingCard(card: card) }
                    .buttonStyle(.plain).disabled(model.busy)
            }
            DisclosureGroup("Photos and screenshots") {
                VStack(alignment: .leading, spacing: 14) {
                    PhotoActivitySection(model: model)
                    ScreenshotsSection(model: model)
                }.padding(.top, 8)
            }
            if !model.coverage.isEmpty {
                Text(model.coverage).font(.footnote).foregroundStyle(.secondary).padding(.top, 4)
            }
        }
    }

    // MARK: iPhone and iPad: photos and screenshots

    @State private var phoneDetail: PhoneDetail?
    enum PhoneDetail { case photos, screenshots }

    @ViewBuilder private var timeline: some View {
        if let phoneDetail {
            VStack(alignment: .leading, spacing: 12) {
                Button { self.phoneDetail = nil } label: { Label("What I found", systemImage: "chevron.backward") }
                    .buttonStyle(.borderless)
                if phoneDetail == .photos { PhotoActivitySection(model: model) } else { ScreenshotsSection(model: model) }
            }
        } else {
            VStack(alignment: .leading, spacing: 12) {
                if model.canReadHistory {
                    Button("Read my history", systemImage: "safari") { model.loadTrail() }.disabled(model.busy)
                } else {
                    Text("What I found").font(.title2.bold())
                }
                Button { phoneDetail = .photos } label: { FindingCard(
                    symbol: "photo.on.rectangle", tint: .pink, title: "Photo activity",
                    headline: photoHeadline, detail: photoDetail) }.buttonStyle(.plain)
                Button { phoneDetail = .screenshots } label: { FindingCard(
                    symbol: "text.viewfinder", tint: .teal, title: "Screenshots you added",
                    headline: screenshotHeadline, detail: screenshotDetail) }.buttonStyle(.plain)
                if !model.canReadHistory {
                    Label("Safari history stays on your Mac.", systemImage: "safari")
                        .font(.footnote).foregroundStyle(.secondary).padding(.top, 4)
                }
            }
        }
    }

    private var photoHeadline: String {
        let n = model.photoEvents.count
        return n == 0 ? "Not read yet" : String(AttributedString(localized: "^[\(n) photo moment](inflect: true)").characters)
    }

    private var photoDetail: String {
        guard let latest = model.photoEvents.max(by: { $0.start < $1.start }) else { return "Tap to read photo activity from this device." }
        let labels = latest.labels.prefix(3).joined(separator: ", ")
        return "Latest: " + latest.start.formatted(.dateTime.month(.abbreviated).day()) + (labels.isEmpty ? "" : ", " + labels)
    }

    private var screenshotHeadline: String {
        let n = model.screenshots.count
        return n == 0 ? "None yet" : String(AttributedString(localized: "^[\(n) screenshot](inflect: true)").characters)
    }

    private var screenshotDetail: String {
        guard let first = model.screenshots.first else { return "Add a booking or receipt to include it." }
        return first.evidence.kind == .unknown ? "Text read on this device" : first.evidence.kind.title + ", read on this device"
    }
}

/// One finding: what it is, the headline fact, and one supporting line.
struct FindingCard: View {
    let symbol: String
    let tint: Color
    let title: String
    let headline: String
    let detail: String

    init(card: TimelineModel.FocusCard) {
        self.init(symbol: card.symbol, tint: card.tint, title: card.title, headline: card.headline, detail: card.detail)
    }

    init(symbol: String, tint: Color, title: String, headline: String, detail: String) {
        self.symbol = symbol; self.tint = tint; self.title = title; self.headline = headline; self.detail = detail
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: symbol)
                .font(.title3).foregroundStyle(tint).frame(width: 30)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.subheadline).foregroundStyle(.secondary)
                Text(headline).font(.title3.weight(.semibold)).lineLimit(2)
                if !detail.isEmpty {
                    Text(detail).font(.footnote).foregroundStyle(.secondary).lineLimit(2)
                }
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
                .accessibilityHidden(true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 12))
        .contentShape(RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .combine)
    }
}

/// The evidence behind one finding, with a way back.
struct FindingDetail: View {
    let model: TimelineModel
    let focus: HistoryFocus
    let back: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Button(action: back) { Label("What I found", systemImage: "chevron.backward") }
                    .buttonStyle(.borderless)
                SelectedEvidence(model: model, focus: focus)
                let starters = model.questions(for: focus)
                if !starters.isEmpty {
                    Divider().padding(.vertical, 4)
                    Text("Ask about this").font(.headline)
                    ForEach(starters.prefix(3), id: \.self) { question in
                        Button { model.askSuggested(question) } label: {
                            Label(question, systemImage: "bubble.left.and.text.bubble.right")
                                .multilineTextAlignment(.leading)
                        }.buttonStyle(.borderless).disabled(model.busy)
                    }
                }
            }.padding(16)
        }
    }
}
