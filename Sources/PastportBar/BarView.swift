import AppKit
import PastportKit
import PastportUI
import SwiftUI
import UniformTypeIdentifiers

/// The Mac window and menu-bar panel. All state lives in `TimelineModel`; this view only
/// lays it out and adds the Mac-only Quit button.
struct BarView: View {
    @Bindable var m: TimelineModel
    @State private var exporting = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
            Divider()
            footer
        }
        .frame(minWidth: 420, minHeight: 560)
        .onAppear { m.start() }
        .fileExporter(
            isPresented: $exporting,
            document: m.experimentData().map(ExperimentDocument.init(data:)),
            contentType: .json,
            defaultFilename: "Pastport-experiment.json"
        ) { m.exportFinished($0) }
    }

    private var header: some View {
        HStack(spacing: 9) {
            Image(systemName: "point.topleft.down.to.point.bottomright.curvepath")
                .font(.body.weight(.semibold))
                .foregroundStyle(.tint)
                .accessibilityHidden(true)
            Text("Pastport").font(.headline)
            Text("on-device").font(.caption2.weight(.medium))
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(.tint.opacity(0.15)).foregroundStyle(.tint).clipShape(Capsule())
            Spacer()
            Menu {
                Picker("Model", selection: $m.model) {
                    ForEach(m.models, id: \.self) { Text($0).tag($0) }
                }
                Divider()
                WindowPicker(days: $m.days)
            } label: {
                Label(m.model.isEmpty ? "Facts only" : shortModel, systemImage: "cpu")
                    .font(.caption)
            }
            .menuStyle(.borderlessButton).fixedSize().disabled(m.busy)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
    }

    private var shortModel: String {
        m.usingApple ? "Apple Intelligence" : m.model
    }

    private var content: some View {
        VStack(spacing: 0) {
            Picker("", selection: $m.tab) {
                ForEach(TimelineModel.Tab.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented).labelsHidden()
            .padding(.horizontal, 14).padding(.vertical, 10)

            SessionStatus(model: m).padding(.horizontal, 14).padding(.bottom, 6)

            Group {
                switch m.tab {
                case .trail:
                    ScrollView {
                        VStack(alignment: .leading, spacing: 14) {
                            HistoryTrailView(model: m)
                            Divider()
                            PhotoActivitySection(model: m)
                            Divider()
                            ScreenshotsSection(model: m)
                        }.padding(14)
                    }
                case .ask:
                    VStack(spacing: 0) {
                        AssistantSourcePicker(model: m).padding(.horizontal, 14).padding(.vertical, 6)
                        if m.assistantSource == .connected {
                            ConnectedAssistantView(model: m.connectedAssistant)
                        } else {
                            EvidenceAskView(model: m)
                        }
                    }
                }
            }.id(m.contentID)
        }
    }

    private var footer: some View {
        HStack {
            Button("Lock & clear", systemImage: "lock.fill") { m.lockAndClear() }
                .controlSize(.small)
            Button("Export to Foundation Lab") { exporting = true }
                .controlSize(.small).disabled(!m.canExport)
                .help("Exports category counts and date coverage only. No URLs, titles, searches, locations or answers. The file remains after Lock & clear.")
            Spacer()
            Button("Quit") { NSApplication.shared.terminate(nil) }.controlSize(.small)
        }.padding(.horizontal, 14).padding(.vertical, 8)
    }
}
