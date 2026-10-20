import AppKit
import PastportKit
import PastportUI
import SwiftUI
import UniformTypeIdentifiers

/// The Mac window and menu-bar panel. All state lives in `TimelineModel`; this view only
/// lays it out and adds the Mac-only menu items.
struct BarView: View {
    @Bindable var m: TimelineModel
    @State private var exporting = false
    @State private var exportDocument: ExperimentDocument?

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            SessionStatus(model: m).padding(.horizontal, 16).padding(.top, 8)
            Group {
                switch m.tab {
                case .trail:
                    HomeView(model: m)
                case .ask:
                    if m.assistantSource == .connected {
                        ConnectedAssistantView(model: m.connectedAssistant)
                    } else {
                        EvidenceAskView(model: m)
                    }
                }
            }.id(m.contentID)
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
        .onChange(of: m.contentID) { exporting = false; exportDocument = nil }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Picker("Section", selection: $m.tab) {
                ForEach(TimelineModel.Tab.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented).labelsHidden().fixedSize()
            Spacer()
            if m.tab == .ask { AnswerSourceMenu(model: m).labelStyle(.iconOnly).menuStyle(.borderlessButton).fixedSize() }
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
