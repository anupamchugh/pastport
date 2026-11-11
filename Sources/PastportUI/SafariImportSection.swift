import PastportKit
import SwiftUI
import UniformTypeIdentifiers

/// iPhone and iPad: choose the ZIP that Safari's "Export Browsing Data" made. Nothing is read until the
/// person chooses a file and passes Face ID, and the result stays in memory until the next lock.
public struct SafariImportSection: View {
    @Bindable var model: TimelineModel
    @State private var choosing = false

    public init(model: TimelineModel) { self.model = model }

    public var body: some View {
        if model.canImportHistory {
            VStack(alignment: .leading, spacing: 10) {
                Label("Safari export", systemImage: "square.and.arrow.down")
                    .font(.headline).foregroundStyle(Palette.ink)
                Text("Export your history from Safari in Settings, then choose the ZIP here. Only history is read. Passwords, cards and bookmarks in the file are ignored.")
                    .font(.footnote).foregroundStyle(Palette.muted)
                Button { choosing = true } label: {
                    Label(model.importedHistoryActive ? "Choose another export" : "Choose Safari export",
                          systemImage: "doc.zipper")
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.bordered)
                .disabled(model.busy)
                .accessibilityHint("Opens the file picker, then asks for Face ID before reading the ZIP")
                if !model.importStatus.isEmpty {
                    Text(model.importStatus).font(.footnote).foregroundStyle(Palette.ink)
                }
            }
            .paperCard()
            .fileImporter(isPresented: $choosing, allowedContentTypes: [.zip], allowsMultipleSelection: false) { result in
                switch result {
                case .success(let urls):
                    if let url = urls.first { model.importSafariExport(from: url) }
                case .failure(let error):
                    if (error as? CocoaError)?.code == .userCancelled { model.importCancelled() } else {
                        model.importFailed()
                    }
                }
            }
        }
    }
}

/// What an imported export shows: the source, its coverage and the most visited sites. Visibly not live history.
public struct ImportedHistoryCard: View {
    let model: TimelineModel

    public init(model: TimelineModel) { self.model = model }

    public var body: some View {
        if model.importedHistoryActive {
            VStack(alignment: .leading, spacing: 8) {
                Label(SafariExport.sourceLabel, systemImage: "safari")
                    .font(.headline).foregroundStyle(Palette.ink)
                if !model.coverage.isEmpty {
                    // The heading already names the source.
                    Text(model.coverage.replacingOccurrences(of: SafariExport.sourceLabel + " · ", with: ""))
                        .font(.footnote).foregroundStyle(Palette.muted)
                }
                if model.busy, !model.status.isEmpty {
                    HStack(spacing: 6) { ProgressView().controlSize(.small); Text(model.status).font(.footnote) }
                }
                ForEach(model.sites.prefix(5)) { site in
                    HStack {
                        Text(site.host).font(.callout).foregroundStyle(Palette.ink)
                        Spacer()
                        Text("\(site.visits)").font(.callout.monospacedDigit()).foregroundStyle(Palette.muted)
                    }
                    .accessibilityElement(children: .combine)
                }
                Text("Ask can answer from this export. Nothing leaves this iPhone.")
                    .font(.caption).foregroundStyle(Palette.muted)
            }
            .paperCard()
        }
    }
}

#if DEBUG
@MainActor private func importPreviewModel(imported: Bool, refused: Bool = false) -> TimelineModel {
    let model = TimelineModel(history: nil, importedHistory: ImportedHistorySource(), days: 30)
    if imported { model.loadDemoImport() }
    if refused { model.loadDemoImportRefusal() }
    return model
}

#Preview("Locked, import offered") {
    LockedTimelineView(model: importPreviewModel(imported: false))
}

#Preview("Locked, import refused, dark") {
    LockedTimelineView(model: importPreviewModel(imported: false, refused: true))
        .preferredColorScheme(.dark)
}

#Preview("Imported") {
    TrailTimelineView(model: importPreviewModel(imported: true))
}

#Preview("Imported, dark") {
    TrailTimelineView(model: importPreviewModel(imported: true)).preferredColorScheme(.dark)
}
#endif
