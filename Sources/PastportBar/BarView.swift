import Foundation
import SwiftUI
import Photos
import PastportKit
import UniformTypeIdentifiers

@MainActor
final class BarModel: ObservableObject {
    enum Tab: String, CaseIterable, Identifiable {
        case trail = "Explore"
        case ask = "Ask"
        var id: String { rawValue }
    }

    struct QA: Identifiable { let id = UUID(); let role: String; var text: String }

    @Published var tab: Tab = .trail
    @Published var days = 90
    enum AssistantSource: String, CaseIterable { case history = "History"; case connected = "Connected tools" }
    @Published var assistantSource: AssistantSource = .history
    @Published var historyFocus: HistoryFocus = .overview
    @Published var recommendedFocuses: [HistoryFocus] = [.overview]
    @Published var suggestedQuestions: [String] = []
    @Published var sites: [HostStat] = []
    @Published var trackerSignals: [TrackerHit] = []
    @Published var historyLoaded = false
    @Published var journeyReceipt: JourneyReceipt?
    let connectedAssistant = ConnectedAssistant()
    private var journey: HistoryJourney?
    private var activeAnswerID: UUID?

    @Published var models: [String] = []
    @Published var model = ""            // selected — defaults to Apple Intelligence

    // This Week
    @Published var brief = ""            // the narrated digest
    @Published var movements: [LocationLeak] = []
    @Published var threads: [IntentThread] = []
    @Published var travel: [Booking] = []
    @Published var themes: [(name: String, visits: Int)] = []

    // Ask (the agent)
    @Published var log: [QA] = []
    @Published var input = ""

    @Published var coverage = ""
    @Published var profile = ""
    @Published var lastAgentRun: HistoryAgent.Run?
    @Published var status = ""
    @Published var busy = false
    @Published var photoEvents: [PhotoEvent] = []
    @Published var photoStatus = "Photos are closed. Read activity when you choose."
    @Published var contentID = UUID()
    private var operation: Task<Void, Never>?
    private var generation = UUID()
    private var started = false

    private var unlocked = false
    private var visits: [Visit] = []     // cached for the agent session

    var usingApple: Bool { model == AppleFoundation.displayName }

    private let demoMode: Bool

    init(demoMode: Bool = ProcessInfo.processInfo.arguments.contains("--demo")
         || ProcessInfo.processInfo.environment["PASTPORT_DEMO"] == "1") {
        self.demoMode = demoMode
        DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("com.apple.screenIsLocked"), object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.lockAndClear() }
        }
    }

    /// Model discovery does not unlock history or read Photos.
    func start() {
        guard !started else { return }
        started = true
        if demoMode {
            models = ["Demo data"]; model = "Demo data"
            loadDemo()
            return
        }
        status = "History is closed. Read your history when you choose."
        Task { @MainActor in
            var list: [String] = AppleFoundation.isAvailable ? [AppleFoundation.displayName] : []
            list += (try? await Ollama.listModels()) ?? []
            models = list
            if model.isEmpty { model = list.first ?? "" }
        }
    }

    func lockAndClear() {
        generation = UUID()
        operation?.cancel(); operation = nil
        unlocked = false; busy = false
        visits = []; movements = []; threads = []; travel = []; themes = []
        photoEvents = []; brief = ""; log = []; input = ""
        coverage = ""; profile = ""; lastAgentRun = nil; journeyReceipt = nil
        sites = []; trackerSignals = []; historyLoaded = false
        historyFocus = .overview; recommendedFocuses = [.overview]; suggestedQuestions = []
        let oldJourney = journey; journey = nil
        activeAnswerID = nil
        Task { await oldJourney?.clear() }
        connectedAssistant.clear()
        photoStatus = "Photos are closed. Read activity when you choose."
        status = "Locked. Cached history, photo activity and answers cleared."
        contentID = UUID()
        if !demoMode { SessionLock.relock() }
    }

    func readPhotos() {
        guard !busy else { return }
        if demoMode {
            let now = Date()
            photoEvents = PhotoEvents.cluster([
                PhotoRecord(time: now, isScreenshot: false, labels: ["landscape"]),
                PhotoRecord(time: now.addingTimeInterval(60), isScreenshot: true, labels: [])
            ])
            photoStatus = "Demo photo activity · fictional records; no library read"
            return
        }
        let token = generation
        let since = days == 0 ? Date.distantPast : Date().addingTimeInterval(-Double(days) * 86400)
        busy = true
        operation = Task { @MainActor in
            defer { if token == generation { busy = false } }
            do {
                // Authentication precedes even the Photos permission prompt.
                let code = await Task.detached {
                    SessionLock.ensureUnlocked(reason: "read your local photo activity", graceMinutes: 0)
                }.value
                guard token == generation, !Task.isCancelled else { SessionLock.relock(); return }
                guard code == 0 else { photoStatus = "Authentication cancelled — Photos kept closed."; return }
                if PHPhotoLibrary.authorizationStatus(for: .readWrite) == .notDetermined {
                    _ = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
                }
                guard token == generation, !Task.isCancelled else { return }
                let records = try await PhotoLibraryProvider().records(since: since, limit: 500)
                guard token == generation, !Task.isCancelled else { return }
                photoEvents = PhotoEvents.cluster(records)
                photoStatus = "Local Photos · up to 500 images; screenshots counted only"
            } catch is CancellationError {
            } catch let error as PhotoLibraryError {
                guard token == generation else { return }
                photoEvents = []; photoStatus = PhotoEvents.statusLine(for: error)
            } catch {
                guard token == generation else { return }
                photoEvents = []; photoStatus = "Photo activity could not be read. Try again after checking Photos access."
            }
        }
    }

    private func loadDemo() {
        let v = DemoData.visits
        visits = v
        let s = Stats.compute(from: v)
        movements = Movements.scan(from: v)
        threads = Threads.scan(from: v, limit: 6)
        travel = Bookings.scan(from: v).filter(\.isTravel)
        themes = s.categories.prefix(6).map { (name: $0.name, visits: $0.visits) }
        sites = s.topHosts
        trackerSignals = Trackers.scan(from: v)
        historyLoaded = true
        recommendedFocuses = availableFocuses
        suggestedQuestions = questions(for: .overview)
        brief = ""
        status = "Demo data · no history read"
    }

    private func unlockAndFetch(token: UUID) async -> [Visit]? {
        if !unlocked {
            status = "Waiting for Touch ID…"
            let ok = await Task.detached {
                SessionLock.ensureUnlocked(reason: "unlock your Safari browsing history", graceMinutes: 480)
            }.value
            guard token == generation, !Task.isCancelled else { SessionLock.relock(); return nil }
            guard ok == 0 else {
                status = ok == 2 ? "No Touch ID / passcode — history kept closed."
                                 : "Touch ID cancelled — history kept closed."
                return nil
            }
            unlocked = true
        }
        guard token == generation, !Task.isCancelled else { return nil }
        status = "Reading history…"
        let d = days
        do {
            let start = ContinuousClock.now
            let result = try await Task.detached { try fetchHistorySnapshot(days: d == 0 ? nil : d) }.value
            guard token == generation, !Task.isCancelled else { return nil }
            coverage = result.scope
            let elapsed = start.duration(to: .now).components
            profile = String(format: "History read: %.2f s", Double(elapsed.seconds) + Double(elapsed.attoseconds) / 1e18)
            return result.visits
        }
        catch {
            guard token == generation else { return nil }
            let t = "\(error)"
            status = t.lowercased().contains("operation not permitted")
                ? "Needs Full Disk Access — enable Pastport in System Settings › Privacy."
                : t
            return nil
        }
    }

    var availableFocuses: [HistoryFocus] {
        var result: [HistoryFocus] = [.overview]
        if !threads.isEmpty { result.append(.research) }
        if !travel.isEmpty { result.append(.travel) }
        if !trackerSignals.isEmpty || !movements.isEmpty { result.append(.privacy) }
        if !movements.isEmpty { result.append(.places) }
        return result
    }

    var focusChoices: [HistoryFocus] {
        var seen = Set<HistoryFocus>()
        return (recommendedFocuses + availableFocuses).filter {
            availableFocuses.contains($0) && seen.insert($0).inserted
        }
    }

    func focusDetail(_ focus: HistoryFocus) -> String {
        switch focus {
        case .overview: return "Sites and categories · exact visit counts"
        case .research: return "\(threads.count) selected search threads"
        case .travel: return "\(travel.count) travel-related page signals"
        case .privacy: return "\(trackerSignals.count) tracking patterns"
        case .places: return "\(movements.count) map links · source evidence"
        }
    }

    func questions(for focus: HistoryFocus) -> [String] {
        switch focus {
        case .overview: return ["Which sites appear most in this retained window?", "What were my recurring research topics?"]
        case .research: return ["Show my repeated search topics and their source queries.", "Narrow this to the last 30 days."]
        case .travel: return ["Which travel-related pages appear, and when?", "Separate checkout visits from confirmation-page signals."]
        case .privacy: return ["Which tracking parameters and redirect patterns were recorded?", "What does this evidence prove, and what remains unknown?"]
        case .places: return ["Which map links contain a named place, and when?", "What do these links show without assuming I visited?"]
        }
    }

    func loadTrail() {
        guard !busy else { return }
        guard !demoMode else { loadDemo(); return }
        let token = generation
        busy = true
        operation = Task { @MainActor in
            defer { if token == generation { busy = false } }
            brief = ""; movements = []; threads = []; travel = []; themes = []; visits = []
            sites = []; trackerSignals = []; historyLoaded = false; log = []; journeyReceipt = nil
            let oldJourney = journey; journey = nil
            await oldJourney?.clear()
            guard let v = await unlockAndFetch(token: token) else { return }
            visits = v
            let scanned = await Task.detached {
                (stats: Stats.compute(from: v, topHostLimit: 15),
                 leaks: Movements.scan(from: v),
                 intents: Threads.scan(from: v, limit: 12),
                 booked: Bookings.scan(from: v).filter(\.isTravel),
                 trackers: Trackers.scan(from: v))
            }.value
            guard token == generation, !Task.isCancelled else { return }
            movements = scanned.leaks; threads = scanned.intents; travel = scanned.booked
            sites = scanned.stats.topHosts; trackerSignals = scanned.trackers
            themes = scanned.stats.categories.map { (name: $0.name, visits: $0.visits) }
            historyLoaded = true; historyFocus = .overview
            recommendedFocuses = availableFocuses; suggestedQuestions = questions(for: .overview)
            guard !v.isEmpty else { status = "No retained visits in this window."; return }
            status = "Evidence ready. Choose a trail to explore."
            let session = HistoryJourney(visits: v, scope: coverage)
            journey = session
            guard usingApple else { return }
            do {
                let result = try await session.recommend("Suggest useful evidence trails to revisit. Prioritize concrete research, travel-related pages and tracking patterns.")
                guard token == generation, !Task.isCancelled else { return }
                recommendedFocuses = result.focuses.filter { availableFocuses.contains($0) }
                if recommendedFocuses.isEmpty { recommendedFocuses = availableFocuses }
                suggestedQuestions = result.suggestedQuestions.isEmpty ? questions(for: .overview) : result.suggestedQuestions
                journeyReceipt = result.receipt; profile = result.receipt.details
                status = "Evidence ready. Choose a trail, then refine it."
            } catch {
                guard token == generation else { return }
                status = "Evidence ready. Apple Intelligence could not suggest trails; you can still explore the records."
            }
        }
    }

    func selectFocus(_ focus: HistoryFocus) {
        guard historyLoaded, !busy else { return }
        historyFocus = focus
        suggestedQuestions = questions(for: focus)
        guard !demoMode, usingApple, let session = journey else { return }
        let token = generation
        busy = true
        operation = Task { @MainActor in
            defer { if token == generation { busy = false } }
            do {
                let result = try await session.recommend("Explore this selected trail and suggest useful follow-up questions.", focus: focus)
                guard token == generation, !Task.isCancelled else { return }
                suggestedQuestions = result.suggestedQuestions.isEmpty ? questions(for: focus) : result.suggestedQuestions
                journeyReceipt = result.receipt; profile = result.receipt.details
                status = "\(focus.title) evidence ready."
            } catch {
                guard token == generation else { return }
                status = "\(focus.title) evidence ready. Suggestions could not be generated."
            }
        }
    }

    func askSuggested(_ question: String) {
        assistantSource = .history; tab = .ask; input = question; ask()
    }

    func ask() {
        let q = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty, !busy, !model.isEmpty else { return }
        input = ""; log.append(QA(role: "user", text: q))
        if demoMode {
            log.append(QA(role: "assistant", text: "Fictional evidence only: the demo includes map links and travel-related pages. Those records do not establish a completed trip. No Safari history was read."))
            return
        }
        let token = generation
        busy = true
        operation = Task { @MainActor in
            defer { if token == generation { busy = false } }
            if visits.isEmpty { guard let v = await unlockAndFetch(token: token) else { return }; visits = v }
            guard !visits.isEmpty else { status = "No history in this window to answer from."; return }
            let pending = QA(role: "assistant", text: "Preparing evidence…")
            log.append(pending)
            activeAnswerID = pending.id
            do {
                let reply: String
                if usingApple {
                    let session: HistoryJourney
                    if let existing = journey { session = existing }
                    else {
                        session = HistoryJourney(visits: visits, scope: coverage)
                        journey = session
                    }
                    let result = try await session.answer(q) { [weak model = self] partial in
                        guard let model, token == model.generation, model.activeAnswerID == pending.id,
                              let index = model.log.firstIndex(where: { $0.id == pending.id }) else { return }
                        model.log[index].text = partial
                    }
                    guard token == generation, !Task.isCancelled else { return }
                    journeyReceipt = result.receipt; profile = result.receipt.details
                    if let answeredFocus = HistoryFocus(rawValue: result.receipt.mode) { historyFocus = answeredFocus }
                    reply = result.text
                } else {
                    let evidence = AskWorkflow.evidence(for: AskWorkflow.intent(for: q), visits: visits)
                    reply = try await Ollama.generate(model: model, prompt: "Use only these retained-history facts. A checkout page is not a completed purchase. Do not change counts.\n" + evidence + "\nQuestion: " + q)
                }
                guard token == generation, !Task.isCancelled,
                      let index = log.firstIndex(where: { $0.id == pending.id }) else { return }
                activeAnswerID = nil
                log[index].text = reply
                status = "Answer ready · source evidence retained for follow-up"
            } catch {
                guard token == generation, let index = log.firstIndex(where: { $0.id == pending.id }) else { return }
                activeAnswerID = nil
                log[index].text = "Apple Intelligence could not finish this answer. The source evidence is still available in Explore."
                status = "Answer could not finish: \(error.localizedDescription)"
            }
        }
    }

    func exportExperiment() {
        guard !busy, !visits.isEmpty else { return }
        let token = generation
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "Pastport-experiment.json"
        panel.message = "Export category counts and date coverage to Foundation Lab. No URLs, titles, searches, locations or answers are included. This file remains after Lock & clear."
        guard panel.runModal() == .OK, let url = panel.url, token == generation, canExport else { return }
        do {
            let data = try HistoryAgent.labExperiment(visits: visits, scope: coverage)
            try data.write(to: url, options: .atomic)
            status = "Experiment exported. In Foundation Lab, use Import Pastport in Library."
        } catch { status = "Experiment export failed: \(error.localizedDescription)" }
    }

    var canExport: Bool { !busy && !visits.isEmpty }

    private func coord(_ v: Double) -> String { String(format: "%.5f", v) }
}

struct BarView: View {
    @ObservedObject var m: BarModel

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
    }

    private var header: some View {
        HStack(spacing: 9) {
            Image(systemName: "point.topleft.down.to.point.bottomright.curvepath")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.tint)
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
                Picker("Window", selection: $m.days) {
                    Text("7 days").tag(7); Text("30 days").tag(30)
                    Text("90 days").tag(90); Text("1 year").tag(365)
                    Text("All retained history").tag(0)
                }.onChange(of: m.days) {
                    m.lockAndClear()
                    m.status = "Window changed. Read history or photo activity for the selected range."
                }
            } label: {
                Label(m.model.isEmpty ? "No model" : shortModel, systemImage: "cpu")
                    .font(.caption)
            }
            .menuStyle(.borderlessButton).fixedSize().disabled(m.busy)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
    }

    private var shortModel: String {
        m.model == AppleFoundation.displayName ? "Apple Intelligence" : m.model
    }

    private var content: some View {
        VStack(spacing: 0) {
            Picker("", selection: $m.tab) {
                ForEach(BarModel.Tab.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented).labelsHidden()
            .padding(.horizontal, 14).padding(.vertical, 10)

            if !m.coverage.isEmpty {
                Text(m.coverage).font(.caption2).foregroundStyle(.secondary)
                    .textSelection(.enabled).padding(.horizontal, 14).padding(.bottom, 4)
            }
            if !m.profile.isEmpty {
                DisclosureGroup("Session details") {
                    Text(m.profile).font(.caption2).foregroundStyle(.secondary)
                        .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                }.font(.caption2).padding(.horizontal, 14).padding(.bottom, 4)
            }
            if !m.status.isEmpty {
                HStack(spacing: 6) {
                    if m.busy { ProgressView().controlSize(.small) }
                    Text(m.status).font(.caption).foregroundStyle(.secondary)
                    Spacer()
                }.padding(.horizontal, 14).padding(.bottom, 6)
            }

            Group {
                switch m.tab {
                case .trail: trail
                case .ask: ask
                }
            }.id(m.contentID)
        }
    }

    private var trail: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if !m.historyLoaded {
                    Text("Find a trail worth revisiting").font(.title3.weight(.semibold))
                    Text("Read your retained Safari history, choose a topic, and inspect the pages behind it.")
                        .font(.callout).foregroundStyle(.secondary)
                    Button("Read history") { m.loadTrail() }.buttonStyle(.borderedProminent).disabled(m.busy)
                } else {
                    HStack {
                        Text("Explore your evidence").font(.title3.weight(.semibold))
                        Spacer()
                        Button("Refresh") { m.loadTrail() }.controlSize(.small).disabled(m.busy)
                    }
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 8) {
                        ForEach(m.focusChoices) { focus in
                            Button { m.selectFocus(focus) } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(focus.title).font(.callout.weight(.semibold))
                                    Text(m.focusDetail(focus)).font(.caption).foregroundStyle(.secondary)
                                        .multilineTextAlignment(.leading)
                                }.frame(maxWidth: .infinity, minHeight: 54, alignment: .leading).padding(5)
                            }
                            .buttonStyle(.bordered)
                            .tint(m.historyFocus == focus ? .accentColor : .secondary)
                            .disabled(m.busy)
                        }
                    }
                    selectedEvidence
                    if !m.suggestedQuestions.isEmpty {
                        Divider()
                        Text("Continue this trail").font(.callout.weight(.semibold))
                        ForEach(m.suggestedQuestions.prefix(3), id: \.self) { question in
                            Button { m.askSuggested(question) } label: {
                                Label(question, systemImage: "arrow.turn.down.right")
                                    .font(.caption).multilineTextAlignment(.leading)
                            }.buttonStyle(.plain).foregroundStyle(.tint).disabled(m.busy)
                        }
                    }
                }
                Divider()
                DisclosureGroup {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(m.photoStatus).font(.caption).foregroundStyle(.secondary)
                        Text("Local images only. No iCloud downloads. Screenshot pixels are excluded.")
                            .font(.caption2).foregroundStyle(.secondary)
                        ForEach(Array(m.photoEvents.enumerated()), id: \.offset) { _, event in
                            VStack(alignment: .leading, spacing: 3) {
                                Text(event.start.formatted(date: .abbreviated, time: .omitted)).font(.caption.weight(.semibold))
                                Text("\(event.photoCount) photos · \(event.screenshotCount) screenshots").font(.caption)
                                if !event.labels.isEmpty { Text("Vision labels: " + event.labels.prefix(5).joined(separator: ", ")).font(.caption2) }
                            }
                        }
                        Button("Read photo activity") { m.readPhotos() }.disabled(m.busy)
                    }.padding(.top, 6)
                } label: {
                    Label("Photo activity", systemImage: "photo.on.rectangle").font(.callout.weight(.medium))
                }
            }.padding(14)
        }
    }

    @ViewBuilder private var selectedEvidence: some View {
        switch m.historyFocus {
        case .overview:
            Text("Sites and categories").font(.headline)
            Text("Counts are page visits in the retained window, not time spent.").font(.caption).foregroundStyle(.secondary)
            FlowChips(items: m.themes.map { "\($0.name) · \($0.visits)" })
            ForEach(m.sites) { site in
                HStack { Text(site.host); Spacer(); Text(site.visits.formatted()).monospacedDigit() }.font(.callout)
            }
        case .research:
            Text("Recorded research threads").font(.headline)
            Text("Selected clusters of related searches. Open a thread to inspect the original wording.").font(.caption).foregroundStyle(.secondary)
            ForEach(m.threads) { ThreadCard(thread: $0) }
        case .travel:
            Text("Travel-related pages").font(.headline)
            Text("A checkout, itinerary or confirmation page is a browsing signal. It does not prove a completed payment or trip.").font(.caption).foregroundStyle(.secondary)
            ForEach(m.travel.prefix(24)) { TravelRow(booking: $0) }
        case .privacy:
            Text("Tracking signals").font(.headline)
            Text("Patterns recorded in links. These do not establish what a third party stored or used.").font(.caption).foregroundStyle(.secondary)
            ForEach(m.trackerSignals.prefix(24)) { signal in
                VStack(alignment: .leading, spacing: 3) {
                    HStack { Text(signal.host).font(.callout.weight(.medium)); Spacer(); Text(signal.count.formatted()).monospacedDigit() }
                    Text(signal.kind.rawValue).font(.caption).foregroundStyle(.secondary)
                    Text(signal.example).font(.caption2.monospaced()).foregroundStyle(.secondary).lineLimit(2).textSelection(.enabled)
                }.padding(.vertical, 4)
            }
            if m.trackerSignals.isEmpty { Text("No tracking parameter or redirect pattern was found in this window.").font(.callout) }
        case .places:
            Text("Map links").font(.headline)
            Text("Coordinates found in recorded URLs, with visit dates. A link does not prove you went there.").font(.caption).foregroundStyle(.secondary)
            ForEach(m.movements.prefix(24)) { MovementCard(leak: $0) }
        }
    }

    private var ask: some View {
        VStack(spacing: 0) {
            Picker("Assistant source", selection: $m.assistantSource) {
                ForEach(BarModel.AssistantSource.allCases, id: \.self) { source in Text(source.rawValue).tag(source) }
            }.pickerStyle(.segmented).padding(.horizontal, 14).padding(.vertical, 6)
            if m.assistantSource == .connected {
                ConnectedAssistantView(model: m.connectedAssistant)
            } else {
            Text("Retained Safari evidence · on-device · \(m.historyFocus.title)")
                .font(.caption2).foregroundStyle(.secondary).padding(.horizontal, 14)
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    if m.log.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Ask about the evidence, then refine it.").font(.callout.weight(.medium))
                            ForEach(m.questions(for: m.historyFocus), id: \.self) { s in
                                Button { m.input = s; m.ask() } label: {
                                    Text("“\(s)”").font(.caption).foregroundStyle(.tint)
                                }.buttonStyle(.plain)
                            }
                        }.frame(maxWidth: .infinity, alignment: .leading).padding(.top, 4)
                    }
                    ForEach(m.log) { Bubble(qa: $0) }
                }.padding(14)
            }
            .defaultScrollAnchor(.bottom)
            .defaultScrollAnchor(.topLeading, for: .alignment)
            HStack(spacing: 8) {
                TextField("Ask about your history…", text: $m.input)
                    .textFieldStyle(.roundedBorder).onSubmit { m.ask() }
                Button { m.ask() } label: { Image(systemName: "arrow.up.circle.fill") }
                    .buttonStyle(.plain).font(.title2).foregroundStyle(.tint)
                    .disabled(m.busy || m.input.isEmpty || m.model.isEmpty)
            }.padding(.horizontal, 14).padding(.vertical, 10)
            }
        }
    }

    private var footer: some View {
        HStack {
            Button("Lock & clear", systemImage: "lock.fill") { m.lockAndClear() }
                .controlSize(.small)
            Button("Export to Foundation Lab") { m.exportExperiment() }
                .controlSize(.small).disabled(!m.canExport)
            Spacer()
            Button("Quit") { NSApplication.shared.terminate(nil) }.controlSize(.small)
        }.padding(.horizontal, 14).padding(.vertical, 8)
    }
}

/// Render model output as markdown. `Text(someString)` shows `**bold**` with the asterisks
/// visible, because SwiftUI only parses markdown from a literal — not from a value produced
/// at runtime. Falls back to the raw text if parsing fails.
func markdown(_ text: String) -> AttributedString {
    (try? AttributedString(
        markdown: text,
        options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
    )) ?? AttributedString(text)
}

/// One commitment in a trip — a ticket, a stay, the paperwork. Denser than a card because
/// travel comes in runs: a flight, then a room, then an arrival form, over a few days.
struct TravelRow: View {
    let booking: Booking

    private var icon: String {
        switch booking.kind {
        case .ticket, .itinerary: "airplane"
        case .checkout: "creditcard"
        case .confirmation: "checkmark.seal"
        }
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: icon).foregroundStyle(.orange).frame(width: 16)
            VStack(alignment: .leading, spacing: 1) {
                // The page title carries the place far more often than the URL does —
                // "Wave House - Arashiyama, Japan" needs no extraction at all.
                Text(booking.title.isEmpty ? Bookings.name(for: booking.host) : booking.title)
                    .font(.callout).lineLimit(1)
                Text(booking.time.formatted(.dateTime.month(.abbreviated).day()))
                    .font(.caption2).foregroundStyle(.tertiary)
            }
            Spacer()
        }
        .padding(.vertical, 5).padding(.horizontal, 10)
        .background(.quaternary.opacity(0.25))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

/// One stretch of "I was trying to work something out". Shows the person's own queries
/// verbatim — the point is recognition, so paraphrasing would defeat it.
struct ThreadCard: View {
    let thread: IntentThread
    @State private var expanded = false
    @State private var revealed = false
    @State private var unlocking = false

    /// One place decides how many queries show, so the button's label can't disagree
    /// with what the list actually renders.
    private var visibleQueries: Int { expanded ? thread.queries.count : 2 }

    /// A sensitive thread shows nothing — not the topic, not the count. The topic word is
    /// the disclosure, so hiding only the queries underneath it would protect nothing.
    private var locked: Bool { thread.isSensitive && !revealed }

    var body: some View {
        if locked { lockedCard } else { openCard }
    }

    private var lockedCard: some View {
        HStack(spacing: 10) {
            Image(systemName: "lock.fill").foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text("A private thread").font(.callout.weight(.semibold))
                Text("Touch ID to view").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button(unlocking ? "…" : "Unlock") {
                unlocking = true
                Task { @MainActor in
                    // graceMinutes 0: a fresh prompt every time. The session-wide unlock
                    // is deliberately not enough for this tier.
                    let ok = await Task.detached {
                        SessionLock.ensureUnlocked(reason: "reveal a private thread", graceMinutes: 0)
                    }.value
                    unlocking = false
                    if ok == 0 { withAnimation(.easeOut(duration: 0.18)) { revealed = true } }
                }
            }
            .buttonStyle(.bordered).controlSize(.small).disabled(unlocking)
        }
        .padding(10)
        .background(.quaternary.opacity(0.3))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private var openCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.teal)
                Text(thread.headline).font(.callout.weight(.semibold))
                Spacer()
                // Count what the card can actually show. `searchCount` counts every search
                // event; the list shows unique phrasings. Displaying "26 searches" above a
                // "show all 3 searches" button reads as a contradiction.
                Text("\(thread.queries.count) searches")
                    .font(.caption2).foregroundStyle(.tertiary)
            }
            // Queries are deduped at construction, so they're safe to identify by value.
            ForEach(thread.queries.prefix(visibleQueries), id: \.self) { q in
                Text("“\(q)”").font(.caption).foregroundStyle(.secondary)
            }
            if !thread.destinations.isEmpty {
                FlowChips(items: Array(thread.destinations.prefix(4)))
            }
            if thread.queries.count > visibleQueries || expanded {
                Button { expanded.toggle() } label: {
                    Text(expanded ? "show less" : "show all \(thread.queries.count) searches")
                        .font(.caption2)
                }.buttonStyle(.plain).foregroundStyle(.tertiary)
            }
        }
        .padding(10)
        .background(.quaternary.opacity(0.3))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

struct MovementCard: View {
    let leak: LocationLeak
    @State private var showReceipt = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                // This card leads the view now, so it carries the weight of a headline.
                Image(systemName: "mappin.and.ellipse").foregroundStyle(.orange)
                Text(leak.headline).font(.headline)
                Spacer()
            }
            HStack(spacing: 8) {
                // A place, not a pair of floats — read out of the URL, never guessed.
                // Coordinates are the fallback when the link carried no address.
                if let place = leak.place {
                    Text(place).font(.callout).foregroundStyle(.secondary)
                } else {
                    Text("\(coord(leak.lat)), \(coord(leak.lng))")
                        .font(.caption.monospaced()).foregroundStyle(.secondary)
                }
                Text(leak.mapProvider).font(.caption2.weight(.medium))
                    .padding(.horizontal, 6).padding(.vertical, 1)
                    .background(.orange.opacity(0.18)).foregroundStyle(.orange).clipShape(Capsule())
                Spacer()
                if let url = URL(string: "https://maps.apple.com/?ll=\(leak.lat),\(leak.lng)") {
                    Link("Open in Maps", destination: url).font(.caption)
                }
            }
            Button { showReceipt.toggle() } label: {
                Text(showReceipt ? "hide the link" : "how do we know this?").font(.caption2)
            }.buttonStyle(.plain).foregroundStyle(.tertiary)
            if showReceipt {
                // The full address and the raw link live here, together: this is the
                // evidence, and it's the part you wouldn't want on screen by default.
                if let address = leak.address {
                    Text(address).font(.caption).textSelection(.enabled)
                }
                Text(leak.decodedURL).font(.caption2.monospaced()).foregroundStyle(.secondary)
                    .textSelection(.enabled).lineLimit(4)
            }
        }
        .padding(11).frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .textBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 9))
        .overlay(RoundedRectangle(cornerRadius: 9).stroke(.quaternary))
    }

    private func coord(_ v: Double) -> String { String(format: "%.5f", v) }
}

struct Bubble: View {
    let qa: BarModel.QA
    private var isUser: Bool { qa.role == "user" }
    var body: some View {
        HStack {
            if isUser { Spacer(minLength: 40) }
            Text(qa.text).font(.callout).textSelection(.enabled)
                .padding(.horizontal, 11).padding(.vertical, 8)
                .background(isUser ? AnyShapeStyle(.tint) : AnyShapeStyle(Color(nsColor: .textBackgroundColor)))
                .foregroundStyle(isUser ? .white : .primary)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(isUser ? nil : RoundedRectangle(cornerRadius: 12).stroke(.quaternary))
            if !isUser { Spacer(minLength: 40) }
        }
        .frame(maxWidth: .infinity, alignment: isUser ? .trailing : .leading)
    }
}

/// A simple wrapping row of chips.
struct FlowChips: View {
    let items: [String]
    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 90), spacing: 6)], alignment: .leading, spacing: 6) {
            ForEach(items, id: \.self) { s in
                Text(s).font(.caption).lineLimit(1)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(.tint.opacity(0.14)).clipShape(Capsule())
            }
        }
    }
}
