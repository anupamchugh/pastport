import PastportKit
import SwiftUI
import UniformTypeIdentifiers
import LinkPresentation

/// Ask over what has been read: starter questions, streamed answers, one Stop.
public struct EvidenceAskView: View {
    @Bindable var model: TimelineModel

    public init(model: TimelineModel) { self.model = model }

    public var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if let question = model.pendingQuestion {
                        PendingQuestionCard(model: model, question: question)
                    } else if model.turns.isEmpty { starters }
                    ForEach(model.turns) { turn in
                        AskTurnView(turn: turn, onFollowUp: { model.input = $0 })
                    }
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
                     ? "Read your history on the Timeline, then come back to ask about it."
                     : "Read your photos or add a screenshot on the Home tab, then come back to ask about it.")
                    .font(.callout).foregroundStyle(.secondary)
                Button(model.canReadHistory ? "Go to Timeline" : "Go to Home") { model.tab = .trail }.buttonStyle(.borderedProminent)
            }
        }
    }
}

/// The question Siri handed over, waiting for an unlock. Nothing has been read to answer it yet.
private struct PendingQuestionCard: View {
    var model: TimelineModel
    let question: String

    private var failed: Bool { model.photoStatus == TimelineModel.unlockFailed }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Unlock to answer").font(.title2.bold())
            Text("“\(question)”").font(.title3)
            Text("Pastport reads your timeline on this device after you unlock, then answers here. Nothing has been read yet.")
                .font(.callout).foregroundStyle(.secondary)
            if failed { NoticeBanner(TimelineModel.unlockFailed, symbol: "faceid") }
            Button { model.unlock() } label: {
                HStack(spacing: 8) {
                    if model.busy { ProgressView().controlSize(.small) }
                    Label(failed ? "Try again" : "Unlock and ask", systemImage: "faceid")
                }
                .font(.headline).frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.borderedProminent)
            .disabled(model.busy)
            .accessibilityHint("Asks for Face ID or your passcode, reads photo activity, then answers the question")
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
    let onFollowUp: ((String) -> Void)?
    @State private var showingMarkdown = false
    @State private var exportingMarkdown = false

    public init(turn: AskTurn, onFollowUp: ((String) -> Void)? = nil) {
        self.turn = turn
        self.onFollowUp = onFollowUp
    }

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
                if !turn.matchingSources.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Matching pages").font(.headline)
                        Text("From your history. Page contents haven’t been read; link parameters are removed for privacy.")
                            .font(.caption).foregroundStyle(.secondary)
                        ForEach(sourceHosts, id: \.self) { host in
                            Text(host).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                            ForEach(turn.matchingSources.filter { ($0.url.host ?? "") == host }) { source in
                                HistoryPageRow(source: source)
                            }
                        }
                        Button("Preview Markdown…") { showingMarkdown = true }.font(.caption)
                        if let onFollowUp {
                            Button("Ask a follow-up") { onFollowUp("Find more related pages") }.font(.caption)
                        }
                    }
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
        .sheet(isPresented: $showingMarkdown) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Research note preview").font(.title2.bold())
                Text("This note contains your question and matching history. Choose where to save it.")
                    .font(.caption).foregroundStyle(.secondary)
                ScrollView { Text(markdownNote).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }
                HStack {
                    Button("Close") { showingMarkdown = false }
                    Spacer()
                    Button("Save Markdown…") { exportingMarkdown = true }.buttonStyle(.borderedProminent)
                }
            }.padding().frame(minWidth: 340, minHeight: 300)
                .fileExporter(isPresented: $exportingMarkdown, document: ResearchNoteDocument(text: markdownNote),
                              contentType: UTType(filenameExtension: "md") ?? .plainText,
                              defaultFilename: "Pastport research") { _ in }
        }
    }

    private static let basisMarker = "\nSource evidence: "
    private var sourceHosts: [String] {
        Array(Set(turn.matchingSources.map { $0.url.host ?? "" })).sorted()
    }

    /// The answer without the evidence lines the model path appends; those sit under "Based on".
    private var shownAnswer: String {
        let answer = turn.answer.components(separatedBy: Self.basisMarker).first ?? turn.answer
        guard !turn.matchingSources.isEmpty else { return answer }
        let lines = answer.components(separatedBy: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("matching visits:") }
        let cleaned = lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? "Found matching pages in your history." : cleaned
    }

    private var markdownNote: String {
        let links = turn.matchingSources.map { "- [\($0.title.replacingOccurrences(of: "]", with: "\\]"))](\($0.url.absoluteString))" }
        return "# Research note\n\nQuestion: \(turn.prompt)\n\n\(shownAnswer)\n\n## Matching pages\n\n" + links.joined(separator: "\n")
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

private struct ResearchNoteDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.plainText] }
    let text: String
    init(text: String) { self.text = text }
    init(configuration: ReadConfiguration) throws {
        text = String(data: configuration.file.regularFileContents ?? Data(), encoding: .utf8) ?? ""
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(text.utf8))
    }
}

/// Metadata requests happen only after the person explicitly chooses to contact the site.
struct HistoryPageRow: View {
    let source: HistoryPageMatch
    @Environment(\.openURL) private var openURL
    @State private var confirmOriginal = false
    @State private var confirmPreview = false
    @State private var loading = false
    @State private var metadata: LPLinkMetadata?
    @State private var previewFailed = false
    @State private var metadataProvider: LPMetadataProvider?
    @State private var previewRequest = UUID()

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Link(destination: source.url) {
                Label(source.title, systemImage: "link").lineLimit(2)
            }
            Text("\(source.url.host ?? "") · \(source.date.formatted(date: .abbreviated, time: .omitted))")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                if source.originalURL != source.url {
                    Button("Open original link…") { confirmOriginal = true }
                }
                Button(loading ? "Loading preview…" : "Load link preview…") { confirmPreview = true }
                    .disabled(loading)
            }.font(.caption)
            if let metadata { HistoryLinkPreview(metadata: metadata).frame(height: 90) }
            if previewFailed { Text("Preview unavailable.").font(.caption).foregroundStyle(.secondary) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .confirmationDialog("Open the original link?", isPresented: $confirmOriginal) {
            Button("Open original link") { openURL(source.originalURL) }
        } message: {
            Text("The original address may contain search terms or other private parameters. Opening it sends the address to the website.")
        }
        .confirmationDialog("Load a link preview?", isPresented: $confirmPreview) {
            Button("Contact website") { loadPreview() }
        } message: {
            Text("Pastport will contact \(source.url.host ?? "the website") using the address without query parameters. The site can see this request and may redirect it to another site.")
        }
        .onChange(of: source.id) { _, _ in clearPreview() }
        .onDisappear { clearPreview() }
    }

    private func loadPreview() {
        clearPreview()
        let request = previewRequest
        let url = source.url
        loading = true
        previewFailed = false
        Task { @MainActor in
            guard request == previewRequest else { return }
            let provider = LPMetadataProvider()
            metadataProvider = provider
            provider.shouldFetchSubresources = false
            do {
                let result = try await provider.startFetchingMetadata(for: url)
                guard request == previewRequest else { return }
                metadata = result
            } catch {
                guard request == previewRequest else { return }
                previewFailed = true
            }
            metadataProvider = nil
            loading = false
        }
    }

    private func clearPreview() {
        previewRequest = UUID()
        metadataProvider?.cancel()
        metadataProvider = nil
        metadata = nil
        loading = false
        previewFailed = false
        confirmPreview = false
        confirmOriginal = false
    }
}

#if os(macOS)
private struct HistoryLinkPreview: NSViewRepresentable {
    let metadata: LPLinkMetadata
    func makeNSView(context: Context) -> LPLinkView { LPLinkView(metadata: metadata) }
    func updateNSView(_ view: LPLinkView, context: Context) { view.metadata = metadata }
}
#else
private struct HistoryLinkPreview: UIViewRepresentable {
    let metadata: LPLinkMetadata
    func makeUIView(context: Context) -> LPLinkView { LPLinkView(metadata: metadata) }
    func updateUIView(_ view: LPLinkView, context: Context) { view.metadata = metadata }
}
#endif

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
