import AppKit
import PastportKit
import PastportMac
import SwiftUI

/// A separate, opt-in view of sanitized Batmobile results. Nothing is persisted or sent to Ask.
struct AlfredReferencesView: View {
    let model: TimelineModel
    @State private var helper: URL?
    @State private var database: URL?
    @State private var references: [String] = []
    @State private var status = "Choose the Batmobile helper and your Alfred database."
    @State private var confirmScan = false
    @State private var scan: Task<Void, Never>?
    @State private var generation = UUID()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Alfred references").font(.title2.bold())
                Text("A trusted Batmobile helper reads the selected database and returns GitHub repository names, not clipboard text.")
                    .foregroundStyle(.secondary)
                if !model.historyLoaded {
                    Text("Unlock your history first to open a private session.").font(.callout)
                } else {
                    HStack {
                        Button(helper == nil ? "Choose Batmobile helper…" : "Change helper…") { chooseHelper() }
                        Text(helper?.lastPathComponent ?? "Not selected").foregroundStyle(.secondary)
                    }
                    HStack {
                        Button(database == nil ? "Choose Alfred database…" : "Change database…") { chooseDatabase() }
                        Text(database?.lastPathComponent ?? "Not selected").foregroundStyle(.secondary)
                    }
                    Button("Read references…") { confirmScan = true }
                        .buttonStyle(.borderedProminent)
                        .disabled(helper == nil || database == nil || scan != nil)
                    Text(status).font(.caption).foregroundStyle(.secondary)
                    if !references.isEmpty {
                        Divider()
                        Text("Repository references").font(.headline)
                        Text("Names found in clipboard history. Batmobile does not check whether they exist or are public.")
                            .font(.caption).foregroundStyle(.secondary)
                        ForEach(references, id: \.self) { reference in
                            if let url = URL(string: "https://github.com/\(reference)") {
                                Link(reference, destination: url).frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }
                }
            }.frame(maxWidth: 720, alignment: .leading).padding(24)
        }
        .confirmationDialog("Run the selected helper?", isPresented: $confirmScan) {
            Button("Read with Batmobile") { startScan() }
        } message: {
            Text("The selected program can read the database and runs with your account’s privileges. It could send data elsewhere. Only continue if you trust this Batmobile repo-history executable; Pastport can’t verify it.")
        }
        .onDisappear { clear() }
    }

    private func chooseHelper() {
        let panel = NSOpenPanel()
        panel.message = "Choose the trusted Batmobile repo-history executable."
        panel.canChooseDirectories = false
        if panel.runModal() == .OK { clearResults(); helper = panel.url }
    }

    private func chooseDatabase() {
        let panel = NSOpenPanel()
        panel.message = "Choose the Alfred clipboard database to read locally."
        panel.canChooseDirectories = false
        if panel.runModal() == .OK { clearResults(); database = panel.url }
    }

    private func startScan() {
        guard let helper, let database else { return }
        clearResults()
        let token = generation
        status = "Reading sanitized references…"
        scan = Task { @MainActor in
            do {
                let found = try await BatmobileReferences.read(helper: helper, database: database)
                guard token == generation, !Task.isCancelled else { return }
                references = found
                status = found.isEmpty ? "No repository references found." : "Found \(found.count) repository references."
            } catch {
                guard token == generation, !Task.isCancelled else { return }
                status = "Couldn’t read references. Check the helper and database permissions."
            }
            scan = nil
        }
    }

    private func clearResults() {
        generation = UUID()
        scan?.cancel(); scan = nil
        references = []
        status = "Choose the Batmobile helper and your Alfred database."
    }

    private func clear() {
        clearResults()
        helper = nil
        database = nil
    }
}
