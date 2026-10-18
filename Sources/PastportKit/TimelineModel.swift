import Foundation
import Observation

/// One question and its answer as shown in Ask.
public struct AskTurn: Identifiable, Sendable, Equatable {
    public enum Status: Sendable, Equatable {
        case answering
        case answered
        /// Stopped by the person; the partial answer stays.
        case stopped
        case failed
    }

    public let id: UUID
    public let prompt: String
    public var answer: String
    public var toolsUsed: [String]
    public var status: Status
    /// Set when code, not the model, wrote the answer.
    public var note: String?

    public init(id: UUID = UUID(), prompt: String, answer: String = "", toolsUsed: [String] = [],
                status: Status = .answering, note: String? = nil) {
        self.id = id
        self.prompt = prompt
        self.answer = answer
        self.toolsUsed = toolsUsed
        self.status = status
        self.note = note
    }
}

/// A local text model other than Apple's, such as Ollama on the Mac.
public struct LocalModels: Sendable {
    public let list: @Sendable () async -> [String]
    public let generate: @Sendable (_ model: String, _ prompt: String) async throws -> String

    public init(list: @escaping @Sendable () async -> [String],
                generate: @escaping @Sendable (_ model: String, _ prompt: String) async throws -> String) {
        self.list = list
        self.generate = generate
    }
}

/// The timeline's state, shared by the Mac and iOS apps. Views observe it and call its actions;
/// every source read goes through an injected adapter.
@MainActor
@Observable
public final class TimelineModel {
    public enum Tab: String, CaseIterable, Identifiable, Sendable {
        case trail = "Explore"
        case ask = "Ask"
        public var id: String { rawValue }
    }

    public enum AssistantSource: String, CaseIterable, Sendable {
        case evidence
        case connected
    }

    public var tab: Tab = .trail
    public var days = 90 {
        didSet {
            guard days != oldValue else { return }
            lockAndClear()
            status = "Window changed. Read your sources again for the selected range."
        }
    }
    public var assistantSource: AssistantSource = .evidence
    public internal(set) var historyFocus: HistoryFocus = .overview
    public internal(set) var recommendedFocuses: [HistoryFocus] = [.overview]
    public internal(set) var suggestedQuestions: [String] = []
    public internal(set) var sites: [HostStat] = []
    public internal(set) var trackerSignals: [TrackerHit] = []
    public internal(set) var historyLoaded = false
    public internal(set) var journeyReceipt: JourneyReceipt?
    public let connectedAssistant = ConnectedAssistant()

    public internal(set) var models: [String] = []
    public var model = ""

    public internal(set) var movements: [LocationLeak] = []
    public internal(set) var threads: [IntentThread] = []
    public internal(set) var travel: [Booking] = []
    public internal(set) var themes: [(name: String, visits: Int)] = []

    public internal(set) var turns: [AskTurn] = []
    public var input = ""

    public internal(set) var coverage = ""
    public internal(set) var profile = ""
    public var status = ""
    public internal(set) var busy = false
    public internal(set) var photoEvents: [PhotoEvent] = []
    public internal(set) var photoStatus = TimelineModel.photosClosed
    public internal(set) var screenshots: [AddedScreenshot] = []
    public internal(set) var screenshotStatus = "Add a screenshot of a booking or receipt. Its text is read on this device and emails, codes and card numbers are hidden."
    /// Changes on every lock so views drop any local disclosure state.
    public internal(set) var contentID = UUID()

    /// False on iPhone and iPad, where iOS does not let apps read Safari history.
    public var canReadHistory: Bool { history != nil }

    @ObservationIgnored private let history: (any HistorySource)?
    @ObservationIgnored private let photos: any PhotoLibraryReading
    @ObservationIgnored private let screenshotReader: ScreenshotReader
    @ObservationIgnored private let authenticator: any Authenticating
    @ObservationIgnored private let timelineAnswerer: any TimelineAnswering
    @ObservationIgnored private let localModels: LocalModels?
    @ObservationIgnored private let appleIntelligenceReady: @Sendable () -> Bool
    #if DEBUG
    /// Debug builds only: fictional data instead of the real sources.
    @ObservationIgnored public var demoMode = false
    #endif
    @ObservationIgnored private var journey: HistoryJourney?
    @ObservationIgnored private var operation: Task<Void, Never>?
    @ObservationIgnored private var generation = UUID()
    @ObservationIgnored private var activeAnswerID: UUID?
    @ObservationIgnored private var started = false
    @ObservationIgnored private var unlocked = false
    @ObservationIgnored var visits: [Visit] = []

    static let photosClosed = "Photos are closed. Read activity when you choose."
    public static let appleModelName = AppleFoundation.displayName

    public init(
        history: (any HistorySource)?,
        photos: any PhotoLibraryReading = PhotoLibraryProvider(),
        screenshotReader: ScreenshotReader = ScreenshotReader(),
        authenticator: any Authenticating = DeviceAuthenticator(),
        timelineAnswerer: any TimelineAnswering = FoundationTimelineAnswerer(),
        localModels: LocalModels? = nil,
        appleIntelligenceReady: @escaping @Sendable () -> Bool = { AppleFoundation.isReady }) {
        self.history = history
        self.photos = photos
        self.screenshotReader = screenshotReader
        self.authenticator = authenticator
        self.timelineAnswerer = timelineAnswerer
        self.localModels = localModels
        self.appleIntelligenceReady = appleIntelligenceReady
    }

    public var usingApple: Bool { model == Self.appleModelName }
    public var isAnswering: Bool { activeAnswerID != nil }
    public var canExport: Bool { !busy && !visits.isEmpty }

    public var evidenceSourceTitle: String { canReadHistory ? "History" : "Timeline" }

    /// Model discovery does not unlock history or read Photos.
    public func start() {
        guard !started else { return }
        started = true
        #if DEBUG
        if demoMode {
            models = ["Demo data"]; model = "Demo data"
            loadDemo()
            return
        }
        #endif
        status = canReadHistory
            ? "History is closed. Read your history when you choose."
            : "Your timeline is closed. Read photo activity or add a screenshot when you choose."
        let ready = appleIntelligenceReady()
        let local = localModels
        Task { @MainActor in
            var list: [String] = ready ? [Self.appleModelName] : []
            list += await local?.list() ?? []
            models = list
            if model.isEmpty { model = list.first ?? "" }
        }
    }

    public func lockAndClear() {
        generation = UUID()
        operation?.cancel(); operation = nil
        unlocked = false; busy = false
        visits = []; movements = []; threads = []; travel = []; themes = []
        photoEvents = []; screenshots = []; turns = []; input = ""
        coverage = ""; profile = ""; journeyReceipt = nil
        sites = []; trackerSignals = []; historyLoaded = false
        historyFocus = .overview; recommendedFocuses = [.overview]; suggestedQuestions = []
        let oldJourney = journey; journey = nil
        activeAnswerID = nil
        Task { await oldJourney?.clear() }
        connectedAssistant.lockAndClear()
        photoStatus = Self.photosClosed
        status = "Locked. Cached history, photo activity, screenshots and answers cleared."
        contentID = UUID()
        #if DEBUG
        if demoMode { return }
        #endif
        authenticator.relock()
    }

    // MARK: Photos

    public func readPhotos() {
        guard !busy else { return }
        #if DEBUG
        if demoMode { loadDemoPhotos(); return }
        #endif
        let token = generation
        let since = days == 0 ? Date.distantPast : Date().addingTimeInterval(-Double(days) * 86400)
        busy = true
        operation = Task { @MainActor in
            defer { if token == generation { busy = false } }
            do {
                // Authentication precedes even the Photos permission prompt.
                let result = await authenticator.unlock(reason: "read your local photo activity", graceMinutes: 0)
                guard token == generation, !Task.isCancelled else { authenticator.relock(); return }
                guard result == .unlocked else { photoStatus = "Authentication cancelled — Photos kept closed."; return }
                await photos.requestAccess()
                guard token == generation, !Task.isCancelled else { return }
                let records = try await photos.records(since: since, limit: 500)
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

    // MARK: Screenshots

    /// Reads one screenshot the person picked. Only scrubbed text is kept; the image is not.
    public func addScreenshot(data: Data, name: String) {
        let token = generation
        screenshotStatus = "Reading the screenshot on this device…"
        let reader = screenshotReader
        Task { @MainActor in
            do {
                let evidence = try await reader.read(imageData: data)
                guard token == generation else { return }
                screenshots.append(AddedScreenshot(name: name, evidence: evidence))
                screenshotStatus = evidence.scrubbedLines.isEmpty
                    ? "No text was found in that image."
                    : "Screenshot read · \(evidence.redactionCount) item\(evidence.redactionCount == 1 ? "" : "s") hidden"
            } catch {
                guard token == generation else { return }
                screenshotStatus = "That image could not be read."
            }
        }
    }

    public func removeScreenshot(_ id: AddedScreenshot.ID) {
        screenshots.removeAll { $0.id == id }
    }

    public var timelineEvidence: TimelineEvidence {
        TimelineEvidence(window: windowTitle, photoEvents: photoEvents, screenshots: screenshots,
                         historyAvailable: canReadHistory)
    }

    public var windowTitle: String {
        switch days {
        case 0: return "all retained"
        case 365: return "last year"
        default: return "last \(days) days"
        }
    }

    // MARK: History (Mac)

    private func unlockAndFetch(token: UUID) async -> [Visit]? {
        guard let history else { return nil }
        if !unlocked {
            status = "Waiting for Touch ID…"
            let result = await authenticator.unlock(reason: "unlock your Safari browsing history", graceMinutes: 480)
            guard token == generation, !Task.isCancelled else { authenticator.relock(); return nil }
            switch result {
            case .unlocked: unlocked = true
            case .unavailable: status = "No Touch ID / passcode — history kept closed."; return nil
            case .cancelled: status = "Touch ID cancelled — history kept closed."; return nil
            }
        }
        guard token == generation, !Task.isCancelled else { return nil }
        status = "Reading history…"
        let d = days
        do {
            let start = ContinuousClock.now
            let result = try await history.snapshot(days: d == 0 ? nil : d)
            guard token == generation, !Task.isCancelled else { return nil }
            coverage = result.scope
            let elapsed = start.duration(to: .now).components
            profile = String(format: "History read: %.2f s", Double(elapsed.seconds) + Double(elapsed.attoseconds) / 1e18)
            return result.visits
        } catch {
            guard token == generation else { return nil }
            let t = "\(error)"
            status = t.lowercased().contains("operation not permitted")
                ? "Needs Full Disk Access — enable Pastport in System Settings › Privacy."
                : t
            return nil
        }
    }

    public var availableFocuses: [HistoryFocus] {
        var result: [HistoryFocus] = [.overview]
        if !threads.isEmpty { result.append(.research) }
        if !travel.isEmpty { result.append(.travel) }
        if !trackerSignals.isEmpty || !movements.isEmpty { result.append(.privacy) }
        if !movements.isEmpty { result.append(.places) }
        return result
    }

    public var focusChoices: [HistoryFocus] {
        var seen = Set<HistoryFocus>()
        return (recommendedFocuses + availableFocuses).filter {
            availableFocuses.contains($0) && seen.insert($0).inserted
        }
    }

    public func focusDetail(_ focus: HistoryFocus) -> String {
        switch focus {
        case .overview: return "Sites and categories · exact visit counts"
        case .research: return "\(threads.count) selected search threads"
        case .travel: return "\(travel.count) travel-related page signals"
        case .privacy: return "\(trackerSignals.count) tracking patterns"
        case .places: return "\(movements.count) map links · source evidence"
        }
    }

    public func questions(for focus: HistoryFocus) -> [String] {
        guard canReadHistory else {
            return ["What does my photo activity show for this window?", "What do the screenshots I added say?"]
        }
        switch focus {
        case .overview: return ["Which sites appear most in this retained window?", "What were my recurring research topics?"]
        case .research: return ["Show my repeated search topics and their source queries.", "Narrow this to the last 30 days."]
        case .travel: return ["Which travel-related pages appear, and when?", "Separate checkout visits from confirmation-page signals."]
        case .privacy: return ["Which tracking parameters and redirect patterns were recorded?", "What does this evidence prove, and what remains unknown?"]
        case .places: return ["Which map links contain a named place, and when?", "What do these links show without assuming I visited?"]
        }
    }

    public func loadTrail() {
        guard !busy else { return }
        #if DEBUG
        if demoMode { loadDemo(); return }
        #endif
        guard canReadHistory else { return }
        let token = generation
        busy = true
        operation = Task { @MainActor in
            defer { if token == generation { busy = false } }
            movements = []; threads = []; travel = []; themes = []; visits = []
            sites = []; trackerSignals = []; historyLoaded = false; turns = []; journeyReceipt = nil
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

    public func selectFocus(_ focus: HistoryFocus) {
        guard historyLoaded, !busy else { return }
        historyFocus = focus
        suggestedQuestions = questions(for: focus)
        #if DEBUG
        if demoMode { return }
        #endif
        guard usingApple, let session = journey else { return }
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

    /// A private thread asks every time; the session-wide unlock is not enough for it.
    public func revealPrivateThread() async -> Bool {
        #if DEBUG
        if demoMode { return true }
        #endif
        return await authenticator.unlock(reason: "reveal a private thread", graceMinutes: 0) == .unlocked
    }

    // MARK: Ask

    public func askSuggested(_ question: String) {
        assistantSource = .evidence; tab = .ask; input = question; ask()
    }

    public var canSend: Bool {
        !busy && !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    public func ask() {
        let q = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty, !busy else { return }
        input = ""
        #if DEBUG
        if demoMode, canReadHistory { appendDemoAnswer(to: q); return }
        #endif
        let turn = AskTurn(prompt: q, answer: "Preparing evidence…")
        turns.append(turn)
        activeAnswerID = turn.id
        let token = generation
        busy = true
        operation = Task { @MainActor in
            defer { if token == generation { busy = false } }
            if canReadHistory {
                await answerFromHistory(q, turnID: turn.id, token: token)
            } else {
                await answerFromTimeline(q, turnID: turn.id, token: token)
            }
        }
    }

    /// Stops the answer in progress. The partial text stays, marked as stopped.
    public func stopAnswer() {
        guard let id = activeAnswerID else { return }
        activeAnswerID = nil
        operation?.cancel(); operation = nil
        busy = false
        if let index = turns.firstIndex(where: { $0.id == id }) {
            if turns[index].answer == "Preparing evidence…" { turns[index].answer = "" }
            turns[index].status = .stopped
        }
        // A cancelled stream may leave the session mid-response; start the next question fresh.
        let oldJourney = journey; journey = nil
        Task { await oldJourney?.clear() }
        status = "Stopped. The partial answer is kept."
    }

    private func isActive(_ turnID: UUID, _ token: UUID) -> Bool {
        token == generation && activeAnswerID == turnID
    }

    private func update(_ turnID: UUID, _ change: (inout AskTurn) -> Void) {
        guard let index = turns.firstIndex(where: { $0.id == turnID }) else { return }
        change(&turns[index])
    }

    private func answerFromHistory(_ q: String, turnID: UUID, token: UUID) async {
        if visits.isEmpty {
            guard let v = await unlockAndFetch(token: token) else {
                if isActive(turnID, token) {
                    activeAnswerID = nil
                    update(turnID) { $0.answer = "History is closed, so there is nothing to answer from."; $0.status = .failed }
                }
                return
            }
            visits = v
        }
        guard isActive(turnID, token) else { return }
        guard !visits.isEmpty else {
            activeAnswerID = nil
            update(turnID) { $0.answer = "No history in this window to answer from."; $0.status = .failed }
            return
        }
        do {
            if usingApple {
                let session: HistoryJourney
                if let existing = journey { session = existing } else {
                    session = HistoryJourney(visits: visits, scope: coverage)
                    journey = session
                }
                let result = try await session.answer(q) { [weak self] partial in
                    guard let self, self.isActive(turnID, token) else { return }
                    self.update(turnID) { $0.answer = partial }
                }
                guard isActive(turnID, token) else { return }
                journeyReceipt = result.receipt; profile = result.receipt.details
                if let answeredFocus = HistoryFocus(rawValue: result.receipt.mode) { historyFocus = answeredFocus }
                update(turnID) { $0.answer = result.text; $0.toolsUsed = result.receipt.toolCalls; $0.status = .answered }
            } else if let localModels, !model.isEmpty {
                let evidence = AskWorkflow.evidence(for: AskWorkflow.intent(for: q), visits: visits)
                let name = model
                let reply = try await localModels.generate(name, "Use only these retained-history facts. A checkout page is not a completed purchase. Do not change counts.\n" + evidence + "\nQuestion: " + q)
                guard isActive(turnID, token) else { return }
                update(turnID) { $0.answer = reply; $0.status = .answered; $0.note = "Answered by \(name)" }
            } else {
                let evidence = AskWorkflow.evidence(for: AskWorkflow.intent(for: q), visits: visits)
                update(turnID) {
                    $0.answer = evidence; $0.status = .answered
                    $0.note = "Apple Intelligence is unavailable, so these are the recorded facts."
                }
            }
            activeAnswerID = nil
            status = "Answer ready · source evidence retained for follow-up"
        } catch {
            guard isActive(turnID, token) else { return }
            activeAnswerID = nil
            update(turnID) {
                $0.answer = "The answer could not finish. The source evidence is still available in Explore."
                $0.status = .failed
            }
            status = "Answer could not finish: \(error.localizedDescription)"
        }
    }

    private func answerFromTimeline(_ q: String, turnID: UUID, token: UUID) async {
        let evidence = timelineEvidence
        do {
            for try await progress in timelineAnswerer.answer(q, evidence: evidence) {
                guard isActive(turnID, token) else { return }
                update(turnID) {
                    $0.answer = progress.text
                    $0.toolsUsed = progress.toolsUsed
                    if case .facts(let reason) = progress.source { $0.note = reason }
                }
            }
            guard isActive(turnID, token) else { return }
            activeAnswerID = nil
            update(turnID) { $0.status = .answered }
            status = "Answer ready"
        } catch {
            guard isActive(turnID, token) else { return }
            activeAnswerID = nil
            update(turnID) {
                $0.answer = evidence.deterministicSummary
                $0.status = .answered
                $0.note = "The model could not finish, so these are the recorded facts."
            }
        }
    }

    #if DEBUG
    /// Development screenshots: open Ask with the first suggested question. Debug builds only.
    public func openAskForScreenshots() {
        start()
        input = questions(for: historyFocus).first ?? ""
        tab = .ask
        ask()
    }
    #endif

    // MARK: Export

    /// Category counts and coverage only; no URLs, titles, searches, places or answers.
    public func experimentData() -> Data? {
        guard canExport else { return nil }
        return try? HistoryAgent.labExperiment(visits: visits, scope: coverage)
    }

    public func exportFinished(_ result: Result<URL, any Error>) {
        switch result {
        case .success: status = "Experiment exported. In Foundation Lab, use Import Pastport in Library."
        case .failure(let error): status = "Experiment export failed: \(error.localizedDescription)"
        }
    }
}
