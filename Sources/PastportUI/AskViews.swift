import PastportKit
import SwiftUI
import UniformTypeIdentifiers

/// Ask over what has been read: starter questions, streamed answers, one Stop.
public struct EvidenceAskView: View {
    @Bindable var model: TimelineModel

    public init(model: TimelineModel) { self.model = model }

    public var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if model.turns.isEmpty { starters }
                    ForEach(model.turns) { AskTurnView(turn: $0) }
                }.padding(16)
            }
            .defaultScrollAnchor(.bottom)
            .defaultScrollAnchor(.topLeading, for: .alignment)
            if model.hasContent { AskComposer(model: model) }
        }
    }

    @ViewBuilder private var starters: some View {
        if model.hasContent {
            VStack(alignment: .leading, spacing: 10) {
                Text(model.canReadHistory ? "Ask about your history" : "Ask about your timeline").font(.title2.bold())
                Text("Answers come from what you have read, on this device.")
                    .font(.footnote).foregroundStyle(.secondary)
                ForEach(model.starterQuestions, id: \.self) { question in
                    Button { model.input = question; model.ask() } label: {
                        Text(question).multilineTextAlignment(.leading).frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 4)
                    }
                    .buttonStyle(.bordered).controlSize(.large).disabled(model.busy)
                }
            }
        } else {
            VStack(alignment: .leading, spacing: 10) {
                Text("Nothing to ask about yet").font(.title2.bold())
                Text(model.canReadHistory
                     ? "Read your history on the Home tab, then come back to ask about it."
                     : "Read your photos or add a screenshot on the Home tab, then come back to ask about it.")
                    .font(.callout).foregroundStyle(.secondary)
                Button("Go to Home") { model.tab = .trail }.buttonStyle(.borderedProminent)
            }
        }
    }
}

public struct AskComposer: View {
    @Bindable var model: TimelineModel

    public init(model: TimelineModel) { self.model = model }

    public var body: some View {
        HStack(spacing: 8) {
            TextField(model.canReadHistory ? "Ask about your history" : "Ask about your timeline",
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
            VStack(alignment: .leading, spacing: 8) {
                Text(answerText).font(.callout).textSelection(.enabled)
                    .foregroundStyle(turn.answer.isEmpty ? .secondary : .primary)
                if !turn.evidenceKinds.isEmpty {
                    HStack(spacing: 6) { ForEach(turn.evidenceKinds, id: \.self) { SourceLabel($0.sourceLabel) } }
                }
                if !basis.isEmpty || !turn.toolsUsed.isEmpty {
                    DisclosureGroup("Based on") {
                        VStack(alignment: .leading, spacing: 4) {
                            if !basis.isEmpty { Text(basis).textSelection(.enabled) }
                            if !turn.toolsUsed.isEmpty { Text("Looked at: " + turn.toolsUsed.joined(separator: ", ")) }
                        }
                        .font(.caption).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }.font(.footnote)
                }
                if let note = turn.note {
                    Text(note).font(.footnote).foregroundStyle(.secondary)
                }
                if let statusLine {
                    Label(statusLine.text, systemImage: statusLine.icon).font(.footnote.weight(.medium))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 14))
            .padding(.trailing, 24)
        }
        .accessibilityElement(children: .contain)
    }

    private static let basisMarker = "\nSource evidence: "

    /// The answer without the evidence lines the model path appends; those sit under "Based on".
    private var shownAnswer: String {
        turn.answer.components(separatedBy: Self.basisMarker).first ?? turn.answer
    }

    private var basis: String {
        let parts = turn.answer.components(separatedBy: Self.basisMarker)
        return parts.dropFirst().joined(separator: "\n")
    }

    private var answerText: AttributedString {
        if turn.answer.isEmpty { return AttributedString(turn.status == .answering ? "Thinking…" : "No answer.") }
        return markdown(shownAnswer)
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
