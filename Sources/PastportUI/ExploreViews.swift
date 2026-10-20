import PastportKit
import PhotosUI
import SwiftUI

struct SelectedEvidence: View {
    let model: TimelineModel
    let focus: HistoryFocus

    var body: some View {
        switch focus {
        case .overview:
            Text("Sites you use most").font(.title3.bold())
            Text("Counts are page visits, not time spent.").font(.caption).foregroundStyle(.secondary)
            FlowChips(items: model.themes.map { "\($0.name) · \($0.visits)" })
            ForEach(model.sites) { site in
                HStack { Text(site.host); Spacer(); Text(site.visits.formatted()).monospacedDigit() }.font(.callout)
                    .accessibilityElement(children: .combine)
            }
        case .research:
            Text("What you looked into").font(.title3.bold())
            Text("Groups of related searches, in your own words.").font(.caption).foregroundStyle(.secondary)
            ForEach(model.threads) { thread in
                ThreadCard(thread: thread) { await model.revealPrivateThread() }
            }
        case .travel:
            Text("Trips and bookings").font(.title3.bold())
            Text("A confirmation or itinerary page in your history shows it was opened. It does not prove anything was bought.").font(.caption).foregroundStyle(.secondary)
            ForEach(model.travel.prefix(24)) { TravelRow(booking: $0) }
        case .privacy:
            Text("Trackers").font(.title3.bold())
            Text("Patterns in the links you opened. They do not show what a company stored.").font(.caption).foregroundStyle(.secondary)
            ForEach(model.trackerSignals.prefix(24)) { signal in
                VStack(alignment: .leading, spacing: 3) {
                    HStack { Text(signal.host).font(.callout.weight(.medium)); Spacer(); Text(signal.count.formatted()).monospacedDigit() }
                    Text(signal.kind.rawValue).font(.caption).foregroundStyle(.secondary)
                    Text(signal.example).font(.caption2.monospaced()).foregroundStyle(.secondary).lineLimit(2).textSelection(.enabled)
                }.padding(.vertical, 4)
            }
            if model.trackerSignals.isEmpty { Text("No tracking parameter or redirect pattern was found in this window.").font(.callout) }
        case .places:
            Text("Links that carry a location").font(.title3.bold())
            Text("Map links you opened. A link does not mean you went there.").font(.caption).foregroundStyle(.secondary)
            ForEach(model.movements.prefix(24)) { MovementCard(leak: $0) }
        }
    }
}

/// Photo bursts from the local library. Screenshots are counted, never inspected.
public struct PhotoActivitySection: View {
    let model: TimelineModel

    public init(model: TimelineModel) { self.model = model }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Photo activity").font(.title2.bold())
            if model.photoEvents.isEmpty {
                Text("No photo activity read yet.").font(.callout).foregroundStyle(.secondary)
            } else {
                Text("Bursts of photos from this device. Screenshots are counted, never looked at.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            ForEach(Array(model.photoEvents.enumerated()), id: \.offset) { _, event in
                VStack(alignment: .leading, spacing: 3) {
                    Text(event.start.formatted(date: .abbreviated, time: .omitted)).font(.headline)
                    Text("^[\(event.photoCount) photo](inflect: true) · ^[\(event.screenshotCount) screenshot](inflect: true)")
                        .font(.subheadline)
                    if !event.labels.isEmpty {
                        Text(event.labels.prefix(5).joined(separator: ", ").capitalized)
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
                .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 12))
                .accessibilityElement(children: .combine)
            }
            Button(model.photoEvents.isEmpty ? "Read my photos" : "Read again") { model.readPhotos() }
                .disabled(model.busy)
        }
    }
}

/// Screenshots the person adds. Text is read on device; emails, codes and card numbers are hidden.
public struct ScreenshotsSection: View {
    let model: TimelineModel

    public init(model: TimelineModel) { self.model = model }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Screenshots you added").font(.title2.bold())
            if model.screenshots.isEmpty {
                Text("Add a screenshot of a booking or receipt. Its text is read on this device, and emails, codes and card numbers are hidden.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            ForEach(model.screenshots) { shot in
                ScreenshotRow(shot: shot) { model.removeScreenshot(shot.id) }
            }
            ScreenshotAdder(model: model)
        }
    }
}

/// The picker that adds a screenshot. Adding one is the person's choice to let its text be read.
struct ScreenshotAdder: View {
    let model: TimelineModel
    @State private var selection: PhotosPickerItem?

    var body: some View {
        PhotosPicker(selection: $selection, matching: .screenshots) {
            Label("Add a screenshot", systemImage: "plus")
        }
        .disabled(model.busy)
        .onChange(of: selection) { _, item in
            guard let item else { return }
            selection = nil
            model.addScreenshot(name: "Screenshot \(model.screenshots.count + 1)") {
                try? await item.loadTransferable(type: Data.self)
            }
        }
    }
}

private struct ScreenshotRow: View {
    let shot: AddedScreenshot
    let remove: () -> Void
    @State private var expanded = false

    private var lines: [String] { shot.evidence.scrubbedLines.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty } }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(shot.evidence.kind == .unknown ? "Screenshot" : shot.evidence.kind.title).font(.headline)
                Spacer()
                Button("Remove", systemImage: "xmark.circle.fill", action: remove)
                    .labelStyle(.iconOnly).buttonStyle(.plain).foregroundStyle(.secondary)
            }
            Text(summary).font(.footnote).foregroundStyle(.secondary)
            ForEach(Array(lines.prefix(expanded ? lines.count : 3).enumerated()), id: \.offset) { _, line in
                Text(line).font(.callout)
            }
            if lines.count > 3 {
                Button(expanded ? "Show less" : "Show all") { expanded.toggle() }
                    .font(.footnote).buttonStyle(.borderless)
            }
        }
        .padding(12).frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 12))
    }

    private var summary: String {
        let hidden = shot.evidence.redactionCount
        let n = lines.count
        let readLines = String(AttributedString(localized: "^[\(n) line](inflect: true) read").characters)
        guard hidden > 0 else { return readLines }
        return readLines + " · " + String(AttributedString(localized: "^[\(hidden) detail](inflect: true) hidden").characters)
    }
}
