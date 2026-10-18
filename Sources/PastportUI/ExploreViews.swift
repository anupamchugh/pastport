import PastportKit
import PhotosUI
import SwiftUI

/// The history trail: read, choose a focus, inspect the evidence behind it.
public struct HistoryTrailView: View {
    let model: TimelineModel
    @Environment(\.horizontalSizeClass) private var sizeClass

    public init(model: TimelineModel) { self.model = model }

    private var columns: [GridItem] {
        sizeClass == .compact ? [GridItem(.flexible())] : [GridItem(.flexible()), GridItem(.flexible())]
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if !model.historyLoaded {
                Text("Find a trail worth revisiting").font(.title3.weight(.semibold))
                Text("Read your retained Safari history, choose a topic, and inspect the pages behind it.")
                    .font(.callout).foregroundStyle(.secondary)
                Button("Read history") { model.loadTrail() }
                    .buttonStyle(.borderedProminent).disabled(model.busy)
            } else {
                HStack {
                    Text("Explore your evidence").font(.title3.weight(.semibold))
                    Spacer()
                    Button("Refresh") { model.loadTrail() }.controlSize(.small).disabled(model.busy)
                }
                LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
                    ForEach(model.focusChoices) { focus in
                        Button { model.selectFocus(focus) } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(focus.title).font(.callout.weight(.semibold))
                                Text(model.focusDetail(focus)).font(.caption).foregroundStyle(.secondary)
                                    .multilineTextAlignment(.leading)
                            }.frame(maxWidth: .infinity, minHeight: 54, alignment: .leading).padding(5)
                        }
                        .buttonStyle(.bordered)
                        .tint(model.historyFocus == focus ? .accentColor : .secondary)
                        .disabled(model.busy)
                        .accessibilityAddTraits(model.historyFocus == focus ? .isSelected : [])
                    }
                }
                SelectedEvidence(model: model)
                if !model.suggestedQuestions.isEmpty {
                    Divider()
                    Text("Continue this trail").font(.callout.weight(.semibold))
                    ForEach(model.suggestedQuestions.prefix(3), id: \.self) { question in
                        Button { model.askSuggested(question) } label: {
                            Label(question, systemImage: "arrow.turn.down.right")
                                .font(.caption).multilineTextAlignment(.leading)
                        }.buttonStyle(.plain).foregroundStyle(.tint).disabled(model.busy)
                    }
                }
            }
        }
    }
}

private struct SelectedEvidence: View {
    let model: TimelineModel

    var body: some View {
        switch model.historyFocus {
        case .overview:
            Text("Sites and categories").font(.headline)
            Text("Counts are page visits in the retained window, not time spent.").font(.caption).foregroundStyle(.secondary)
            FlowChips(items: model.themes.map { "\($0.name) · \($0.visits)" })
            ForEach(model.sites) { site in
                HStack { Text(site.host); Spacer(); Text(site.visits.formatted()).monospacedDigit() }.font(.callout)
                    .accessibilityElement(children: .combine)
            }
        case .research:
            Text("Recorded research threads").font(.headline)
            Text("Selected clusters of related searches. Open a thread to inspect the original wording.").font(.caption).foregroundStyle(.secondary)
            ForEach(model.threads) { thread in
                ThreadCard(thread: thread) { await model.revealPrivateThread() }
            }
        case .travel:
            Text("Travel-related pages").font(.headline)
            Text("A checkout, itinerary or confirmation page is a browsing signal. It does not prove a completed payment or trip.").font(.caption).foregroundStyle(.secondary)
            ForEach(model.travel.prefix(24)) { TravelRow(booking: $0) }
        case .privacy:
            Text("Tracking signals").font(.headline)
            Text("Patterns recorded in links. These do not establish what a third party stored or used.").font(.caption).foregroundStyle(.secondary)
            ForEach(model.trackerSignals.prefix(24)) { signal in
                VStack(alignment: .leading, spacing: 3) {
                    HStack { Text(signal.host).font(.callout.weight(.medium)); Spacer(); Text(signal.count.formatted()).monospacedDigit() }
                    Text(signal.kind.rawValue).font(.caption).foregroundStyle(.secondary)
                    Text(signal.example).font(.caption2.monospaced()).foregroundStyle(.secondary).lineLimit(2).textSelection(.enabled)
                }.padding(.vertical, 4)
            }
            if model.trackerSignals.isEmpty { Text("No tracking parameter or redirect pattern was found in this window.").font(.callout) }
        case .places:
            Text("Map links").font(.headline)
            Text("Coordinates found in recorded URLs, with visit dates. A link does not prove you went there.").font(.caption).foregroundStyle(.secondary)
            ForEach(model.movements.prefix(24)) { MovementCard(leak: $0) }
        }
    }
}

/// Photo bursts from the local library. Screenshots are counted, never inspected.
public struct PhotoActivitySection: View {
    let model: TimelineModel

    public init(model: TimelineModel) { self.model = model }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Photo activity", systemImage: "photo.on.rectangle").font(.headline)
            Text(model.photoStatus).font(.caption).foregroundStyle(.secondary)
            Text("Local images only. No iCloud downloads. Screenshot pixels are excluded.")
                .font(.caption2).foregroundStyle(.secondary)
            ForEach(Array(model.photoEvents.enumerated()), id: \.offset) { _, event in
                VStack(alignment: .leading, spacing: 3) {
                    Text(event.start.formatted(date: .abbreviated, time: .omitted)).font(.caption.weight(.semibold))
                    Text("\(event.photoCount) photos · \(event.screenshotCount) screenshots").font(.caption)
                    if !event.labels.isEmpty {
                        Text("Scene labels: " + event.labels.prefix(5).joined(separator: ", ")).font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(8).frame(maxWidth: .infinity, alignment: .leading)
                .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 8))
                .accessibilityElement(children: .combine)
            }
            Button("Read photo activity") { model.readPhotos() }.disabled(model.busy)
        }
    }
}

/// Screenshots the person adds. Text is read on device; emails, codes and card numbers are hidden.
public struct ScreenshotsSection: View {
    let model: TimelineModel
    @State private var selection: PhotosPickerItem?

    public init(model: TimelineModel) { self.model = model }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Screenshots you added", systemImage: "text.viewfinder").font(.headline)
            Text(model.screenshotStatus).font(.caption).foregroundStyle(.secondary)
            ForEach(model.screenshots) { shot in
                ScreenshotRow(shot: shot) { model.removeScreenshot(shot.id) }
            }
            PhotosPicker(selection: $selection, matching: .screenshots) {
                Label("Add a screenshot", systemImage: "plus")
            }
            .disabled(model.busy)
        }
        .onChange(of: selection) { _, item in
            guard let item else { return }
            selection = nil
            Task { @MainActor in
                guard let data = try? await item.loadTransferable(type: Data.self) else { return }
                model.addScreenshot(data: data, name: "Screenshot \(model.screenshots.count + 1)")
            }
        }
    }
}

private struct ScreenshotRow: View {
    let shot: AddedScreenshot
    let remove: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(shot.name).font(.callout.weight(.semibold))
                Text(shot.evidence.kind.title).font(.caption2.weight(.medium))
                    .padding(.horizontal, 6).padding(.vertical, 1)
                    .background(.tint.opacity(0.14)).clipShape(Capsule())
                Spacer()
                Button("Remove", systemImage: "xmark.circle", action: remove)
                    .labelStyle(.iconOnly).buttonStyle(.plain).foregroundStyle(.secondary)
            }
            Text("\(shot.evidence.redactionCount) hidden · \(shot.evidence.scrubbedLines.count) lines")
                .font(.caption2).foregroundStyle(.secondary)
            Text(shot.evidence.scrubbedLines.prefix(8).joined(separator: "\n"))
                .font(.caption.monospaced()).textSelection(.enabled)
        }
        .padding(8).frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 8))
    }
}
