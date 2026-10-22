import PastportKit
import SwiftUI

/// The Add tab: pick one screenshot, see its text with sensitive items hidden, keep it on the
/// timeline. Needs no unlock, because it reads no library.
public struct AddScreen: View {
    let model: TimelineModel

    public init(model: TimelineModel) { self.model = model }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Add a screenshot").font(.system(.title, design: .serif).bold()).foregroundStyle(Palette.ink)
                    Text("A ticket or a confirmation works best. Emails, one-time codes and card numbers are replaced before you see it. The image is not kept.")
                        .font(.callout).foregroundStyle(Palette.muted)
                }
                ScreenshotAdder(model: model)
                    .buttonStyle(.borderedProminent).tint(Palette.accent.light).controlSize(.large)
                Text(model.screenshotStatus).font(.footnote).foregroundStyle(Palette.muted)
                ForEach(model.screenshots.reversed()) { shot in
                    AddedShotCard(shot: shot) { model.removeScreenshot(shot.id) }
                }
                if model.isLocked, !model.screenshots.isEmpty {
                    Text("These show on the Timeline after you unlock it.")
                        .font(.footnote).foregroundStyle(Palette.muted)
                }
            }
            .padding(16)
            .frame(maxWidth: 640, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(Palette.background)
    }
}

/// One added screenshot: its kind, any booking found, per-kind hidden counts, and the
/// scrubbed text with each hidden item drawn as a dark bar.
struct AddedShotCard: View {
    let shot: AddedScreenshot
    let remove: () -> Void

    private var lines: [String] {
        shot.evidence.scrubbedLines.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                SourceLabel(EvidenceCard.Source.screenshot.rawValue)
                Spacer()
                Button("Remove", systemImage: "xmark.circle.fill", action: remove)
                    .labelStyle(.iconOnly).buttonStyle(.plain).foregroundStyle(Palette.muted)
                    .frame(minWidth: 44, minHeight: 44)
            }
            if let booking = BookingFromScreenshot.detect(shot.evidence) {
                Text("\(EvidenceCards.title(for: booking.kind)) dated \(booking.date.formatted(.dateTime.day().month(.abbreviated)))")
                    .font(.system(.title3, design: .serif).weight(.semibold)).foregroundStyle(Palette.ink)
            } else {
                Text(shot.evidence.kind == .unknown ? "Screenshot" : shot.evidence.kind.title)
                    .font(.system(.title3, design: .serif).weight(.semibold)).foregroundStyle(Palette.ink)
            }
            let hidden = EvidenceCards.redactionDetails(shot.evidence.redactions)
            Text(hidden.isEmpty ? "Nothing sensitive found." : "Hidden: " + hidden.joined(separator: ", "))
                .font(.footnote).foregroundStyle(Palette.muted)
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(lines.prefix(8).enumerated()), id: \.offset) { _, line in
                    RedactedLine(line: line)
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.card2, in: RoundedRectangle(cornerRadius: 12))
        }
        .paperCard()
    }
}

/// A scrubbed line where [EMAIL], [OTP] and [CARD] become solid bars. VoiceOver reads the
/// kind only, such as "Hidden: email address", never the content.
struct RedactedLine: View {
    let line: String

    private static let tokens: [(token: String, spoken: String)] = [
        ("[EMAIL]", "email address"), ("[OTP]", "one-time code"), ("[CARD]", "card number"),
    ]

    private var segments: [(text: String, hidden: Bool)] {
        var result: [(text: String, hidden: Bool)] = []
        var rest = Substring(line)
        while !rest.isEmpty {
            let next = Self.tokens.compactMap { item in rest.range(of: item.token).map { ($0, item.token) } }
                .min { $0.0.lowerBound < $1.0.lowerBound }
            guard let range = next?.0 else { result.append((String(rest), false)); break }
            if range.lowerBound > rest.startIndex { result.append((String(rest[..<range.lowerBound]), false)) }
            result.append((String(rest[range]), true))
            rest = rest[range.upperBound...]
        }
        return result
    }

    private var spoken: String {
        Self.tokens.reduce(line) { $0.replacingOccurrences(of: $1.token, with: "Hidden: \($1.spoken)") }
    }

    var body: some View {
        segments.reduce(Text(verbatim: "")) { text, segment in
            let piece = segment.hidden
                ? Text(verbatim: String(repeating: "\u{2588}", count: 8)).foregroundStyle(Palette.redaction)
                : Text(verbatim: segment.text).foregroundStyle(Palette.ink)
            return Text("\(text)\(piece)")
        }
        .font(.callout.monospaced())
        .accessibilityLabel(spoken)
    }
}

#if DEBUG
#Preview("Add") {
    let model = TimelineModel(history: nil, days: 30)
    model.demoMode = true
    model.start()
    return AddScreen(model: model)
}
#endif
