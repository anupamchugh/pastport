import AppKit
import PastportKit
import PastportMac
import PastportUI
import SwiftUI
import UniformTypeIdentifiers

/// The Mac window and menu-bar panel. All state lives in `TimelineModel`; this view only
/// lays it out and adds the Mac-only menu items.
struct BarView: View {
    @Bindable var m: TimelineModel
    @State private var exporting = false
    @State private var exportDocument: ExperimentDocument?
    @State private var showingAlfred = false
    @State private var showingCodex = false

    var body: some View {
        GeometryReader { geometry in
            HStack(spacing: 0) {
                if geometry.size.width >= 760 {
                    sidebar
                    Divider()
                }
                VStack(spacing: 0) {
                    header(showTabs: geometry.size.width < 760)
                    Divider()
                    SessionStatus(model: m).padding(.horizontal, 16).padding(.top, 8)
                    Group {
                        if showingCodex {
                            CodexConnectionView(model: m)
                        } else if showingAlfred {
                            AlfredReferencesView(model: m)
                        } else { switch m.tab {
                        case .trail, .add, .privacy:
                            HomeView(model: m)
                        case .ask:
                            if m.assistantSource == .connected {
                                ConnectedAssistantView(model: m.connectedAssistant)
                            } else {
                                EvidenceAskView(model: m)
                            }
                        } }
                    }.id(m.contentID)
                }
            }
        }
        .frame(minWidth: 420, minHeight: 560)
        .onAppear { m.start() }
        .fileExporter(
            isPresented: $exporting,
            document: exportDocument,
            contentType: .json,
            defaultFilename: "Pastport-experiment.json"
        ) { m.exportFinished($0); exportDocument = nil }
        // A lock while the save panel is open cancels the export.
        .onChange(of: m.contentID) { exporting = false; exportDocument = nil; showingAlfred = false; showingCodex = false }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Pastport", systemImage: "clock.arrow.circlepath")
                .font(.headline).padding(.horizontal, 10).padding(.bottom, 18)
            sidebarButton("Timeline", symbol: "clock", tab: .trail)
            sidebarButton("Ask", symbol: "bubble.left.and.text.bubble.right", tab: .ask)
            Button { showingAlfred = true; showingCodex = false } label: {
                Label("Alfred", systemImage: "link")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 10).padding(.vertical, 8)
                    .background(showingAlfred ? Color.accentColor.opacity(0.2) : Color.clear,
                                in: RoundedRectangle(cornerRadius: 8))
            }.buttonStyle(.plain)
            Button { showingCodex = true; showingAlfred = false } label: {
                Label("Codex", systemImage: "terminal")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 10).padding(.vertical, 8)
                    .background(showingCodex ? Color.accentColor.opacity(0.2) : Color.clear,
                                in: RoundedRectangle(cornerRadius: 8))
            }.buttonStyle(.plain)
            Spacer()
            Label("On this Mac", systemImage: "lock.shield")
                .font(.caption).foregroundStyle(.secondary).padding(10)
        }
        .padding(.horizontal, 10).padding(.top, 20).padding(.bottom, 12)
        .frame(width: 190).frame(maxHeight: .infinity, alignment: .topLeading)
        .background(.bar)
    }

    private func sidebarButton(_ title: String, symbol: String, tab: TimelineModel.Tab) -> some View {
        Button { showingAlfred = false; showingCodex = false; m.tab = tab } label: {
            Label(title, systemImage: symbol)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10).padding(.vertical, 8)
                .background(!showingAlfred && !showingCodex && m.tab == tab ? Color.accentColor.opacity(0.2) : Color.clear,
                            in: RoundedRectangle(cornerRadius: 8))
        }.buttonStyle(.plain)
    }

    private func header(showTabs: Bool) -> some View {
        HStack(spacing: 12) {
            if showTabs {
                Button("Timeline") { showingAlfred = false; showingCodex = false; m.tab = .trail }
                Button("Ask") { showingAlfred = false; showingCodex = false; m.tab = .ask }
                Button("Alfred") { showingAlfred = true; showingCodex = false }
                    .accessibilityLabel("Alfred references")
                Button("Codex") { showingCodex = true; showingAlfred = false }
                    .accessibilityLabel("Codex connection")
            } else {
                Text(showingCodex ? "Codex" : showingAlfred ? "Alfred" : (m.tab == .ask ? "Ask Pastport" : "Your timeline")).font(.headline)
            }
            Spacer()
            if m.tab == .ask && !showingAlfred { AnswerSourceMenu(model: m).labelStyle(.iconOnly).menuStyle(.borderlessButton).fixedSize() }
            Menu {
                Button("Lock and clear", systemImage: "lock") { m.lockAndClear() }
                    .disabled(!m.hasContent)
                Divider()
                if !m.models.isEmpty {
                    Picker("Model", selection: $m.model) {
                        ForEach(m.models, id: \.self) { Text($0).tag($0) }
                    }
                }
                WindowPicker(days: $m.days)
                Divider()
                Button("Export summary for Foundation Lab…") {
                    exportDocument = m.experimentData().map(ExperimentDocument.init(data:))
                    exporting = exportDocument != nil
                }
                .disabled(!m.canExport)
                Divider()
                Button("Quit Pastport") { NSApplication.shared.terminate(nil) }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton).fixedSize().disabled(m.busy && m.tab != .ask)
            .help("More")
            .accessibilityLabel("More")
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
    }
}

#if DEBUG
/// Starts locked; reading Safari still requires the normal user action and permissions.
#Preview("Pastport Mac — history access") {
    BarView(m: TimelineModel(history: SafariHistorySource()))
        .frame(width: 1000, height: 700)
}
#endif
