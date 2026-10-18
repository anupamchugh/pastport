import PastportKit
import SwiftUI
import UniformTypeIdentifiers

/// Ask over the evidence already read: streamed answers, one Stop, and the tools each answer used.
public struct EvidenceAskView: View {
    @Bindable var model: TimelineModel

    public init(model: TimelineModel) { self.model = model }

    private var scopeLine: String {
        model.canReadHistory
            ? "Retained Safari evidence · on-device · \(model.historyFocus.title)"
            : "Photo activity and screenshots you added · on-device · Safari history stays on your Mac"
    }

    public var body: some View {
        VStack(spacing: 0) {
            Text(scopeLine)
                .font(.caption2).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14)
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if model.turns.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Ask about the evidence, then refine it.").font(.callout.weight(.medium))
                            ForEach(model.questions(for: model.historyFocus), id: \.self) { s in
                                Button { model.input = s; model.ask() } label: {
                                    Text("“\(s)”").font(.caption).foregroundStyle(.tint)
                                        .multilineTextAlignment(.leading)
                                }.buttonStyle(.plain).disabled(model.busy)
                            }
                        }.frame(maxWidth: .infinity, alignment: .leading).padding(.top, 4)
                    }
                    ForEach(model.turns) { AskTurnView(turn: $0) }
                }.padding(14)
            }
            .defaultScrollAnchor(.bottom)
            .defaultScrollAnchor(.topLeading, for: .alignment)
            AskComposer(model: model)
        }
    }
}

public struct AskComposer: View {
    @Bindable var model: TimelineModel

    public init(model: TimelineModel) { self.model = model }

    public var body: some View {
        HStack(spacing: 8) {
            TextField(model.canReadHistory ? "Ask about your history…" : "Ask about your timeline…",
                      text: $model.input, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(1...4)
                .onSubmit { model.ask() }
            if model.isAnswering {
                Button { model.stopAnswer() } label: { Image(systemName: "stop.circle.fill") }
                    .buttonStyle(.plain).font(.title2).foregroundStyle(.tint)
                    .accessibilityLabel("Stop answer")
            } else {
                Button { model.ask() } label: { Image(systemName: "arrow.up.circle.fill") }
                    .buttonStyle(.plain).font(.title2).foregroundStyle(.tint)
                    .disabled(!model.canSend)
                    .accessibilityLabel("Send question")
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
    }
}

/// One question, its answer, the tools the answer used, and how it ended.
public struct AskTurnView: View {
    let turn: AskTurn

    public init(turn: AskTurn) { self.turn = turn }

    public var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Spacer(minLength: 40)
                Text(turn.prompt).font(.callout).textSelection(.enabled)
                    .padding(.horizontal, 11).padding(.vertical, 8)
                    .background(.tint, in: RoundedRectangle(cornerRadius: 12))
                    .foregroundStyle(.white)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text(answerText).font(.callout).textSelection(.enabled)
                    .foregroundStyle(turn.answer.isEmpty ? .secondary : .primary)
                if !turn.toolsUsed.isEmpty {
                    Label("Tools used: " + turn.toolsUsed.joined(separator: ", "), systemImage: "wrench.and.screwdriver")
                        .font(.caption2).foregroundStyle(.secondary)
                }
                if let note = turn.note {
                    Label(note, systemImage: "info.circle").font(.caption2).foregroundStyle(.secondary)
                }
                if let statusLine {
                    Label(statusLine.text, systemImage: statusLine.icon).font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 11).padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.background, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(.quaternary))
            .padding(.trailing, 24)
        }
        .accessibilityElement(children: .contain)
    }

    private var answerText: AttributedString {
        if turn.answer.isEmpty { return AttributedString(turn.status == .answering ? "Thinking…" : "No answer.") }
        return markdown(turn.answer)
    }

    private var statusLine: (text: String, icon: String)? {
        switch turn.status {
        case .answering, .answered: nil
        case .stopped: ("Stopped", "stop.circle")
        case .failed: ("Did not finish", "exclamationmark.circle")
        }
    }
}

/// Render model output as markdown. `Text(someString)` shows `**bold**` with the asterisks
/// visible, because SwiftUI only parses markdown from a literal. Falls back to the raw text.
public func markdown(_ text: String) -> AttributedString {
    (try? AttributedString(
        markdown: text,
        options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
    )) ?? AttributedString(text)
}

/// The Foundation Lab experiment as a file for `fileExporter`.
public struct ExperimentDocument: FileDocument {
    public static let readableContentTypes: [UTType] = [.json]
    public let data: Data

    public init(data: Data) { self.data = data }

    public init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    public func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
