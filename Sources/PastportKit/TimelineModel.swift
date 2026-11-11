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
    /// Source labels the answer used, kept only where a matching tool ran.
    public var evidenceKinds: [EvidenceKind] = []
    public var matchingSources: [HistoryPageMatch] = []

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

/// A checked result from one stage of an in-memory Safari trail.
public struct AgentTrailStop: Identifiable, Sendable {
    public let focus: HistoryFocus
    public let answer: HistoryAnswer
    public var id: HistoryFocus { focus }
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
    /// iPhone and iPad show all four tabs; the Mac shows `macTabs`.
    public enum Tab: String, CaseIterable, Identifiable, Sendable {
        case trail = "Home"
        case ask = "Ask"
        case add = "Add"
        case privacy = "Privacy"
        public var id: String { rawValue }

        public static let macTabs: [Tab] = [.trail, .ask]
    }

    public enum AssistantSource: String, CaseIterable, Sendable {
        case evidence
        case connected
    }

    /// The window choices on iPhone and iPad. "All retained" stays a Mac choice.
    public static let iPhoneWindows = [7, 30, 90, 365]

    public var tab: Tab = .trail
    public var days = 90 {
        didSet {
            guard days != oldValue else { return }
            lockAndClear()
            status = "Window changed. Read your sources again for the selected range."
        }
    }
    public var assistantSource: AssistantSource = .evidence
    /// The open iPhone trail. Resets to Overview on every lock.
    public var trail: TimelineTrail = .overview
    public internal(set) var historyFocus: HistoryFocus = .overview
    public internal(set) var recommendedFocuses: [HistoryFocus] = [.overview]
    public internal(set) var suggestedQuestions: [String] = []
    public internal(set) var sites: [HostStat] = []
    public internal(set) var trackerSignals: [TrackerHit] = []
    public internal(set) var historyLoaded = false
    public internal(set) var journeyReceipt: JourneyReceipt?
    public internal(set) var agentTrailStops: [AgentTrailStop] = []
    public internal(set) var agentTrailStatus = ""
    public internal(set) var agentTrailRunning = false
    /// Session state an app layer registered through `sessionState(_:make:)`. Every lock clears it.
    @ObservationIgnored var sessionScoped: [ObjectIdentifier: any SessionScoped] = [:]
    /// The opt-in Codex connection (Mac). Off at every launch; every lock ends its approvals.
    public let codex = McpConnection()

    public internal(set) var models: [String] = []
    public var model = ""

    public internal(set) var movements: [LocationLeak] = []
    public internal(set) var threads: [IntentThread] = []
    public internal(set) var travel: [Booking] = []
    public internal(set) var themes: [(name: String, visits: Int)] = []

    public internal(set) var turns: [AskTurn] = []
    /// The Skeptic's review of each finished answer, in memory only. Every lock clears it.
    public internal(set) var skepticReviews: [AskTurn.ID: SkepticState] = [:]
    /// The Historian's story of the window, in memory only. Every lock clears it.
    public internal(set) var historian: HistorianStory?
    public var input = ""
    /// A question the "Ask Pastport" App Intent handed over. It waits, unread and unanswered,
    /// until the person unlocks; then it is asked once. Every lock clears it.
    public internal(set) var pendingQuestion: String?

    public internal(set) var coverage = ""
    public internal(set) var profile = ""
    public var status = ""
    public internal(set) var busy = false
    public internal(set) var photoEvents: [PhotoEvent] = []
    public internal(set) var photoStatus = TimelineModel.photosClosed
    public internal(set) var screenshots: [AddedScreenshot] = []
    public internal(set) var screenshotStatus = TimelineModel.screenshotsClosed
    /// Changes on every lock so views drop any local disclosure state.
    public internal(set) var contentID = UUID()
    /// True from launch and after every lock. `unlock()` clears it once a photo read pass ends.
    public internal(set) var isLocked = true

    /// False on iPhone and iPad until the person imports a Safari export: iOS does not let apps read
    /// Safari history, so the only source there is a ZIP they chose.
    public var canReadHistory: Bool { history != nil || importedHistoryActive }
    /// True where a Safari export can be chosen (iPhone and iPad).
    public var canImportHistory: Bool { importedHistory != nil }
    /// True from a successful import until the next lock. Observed: copy and cards depend on it.
    public internal(set) var importedHistoryActive = false
    /// The last import's outcome in plain words, shown beside the import button. Never names a file.
    public internal(set) var importStatus = ""
    /// The imported Reading List, from the export's Bookmarks.html. Empty until an import and after every lock.
    public var readingList: [ReadingListItem] { importedHistoryActive ? (importedHistory?.readingList ?? []) : [] }

    @ObservationIgnored private let history: (any HistorySource)?
    @ObservationIgnored let importedHistory: ImportedHistorySource?
    private var activeHistory: (any HistorySource)? { history ?? (importedHistoryActive ? importedHistory : nil) }
    @ObservationIgnored private let photos: any PhotoLibraryReading
    @ObservationIgnored private let screenshotReader: ScreenshotReader
    @ObservationIgnored private let authenticator: any Authenticating
    @ObservationIgnored private let timelineAnswerer: any TimelineAnswering
    @ObservationIgnored private let localModels: LocalModels?
    @ObservationIgnored private let appleIntelligenceReady: @Sendable () -> Bool
    @ObservationIgnored private let skeptic: any SkepticReviewing
    @ObservationIgnored private let historianNarrator: any HistorianNarrating
    #if DEBUG
    /// Debug builds only: fictional data instead of the real sources.
    @ObservationIgnored public var demoMode = false
    #endif
    @ObservationIgnored private var journey: HistoryJourney?
    @ObservationIgnored private var operation: Task<Void, Never>?
    /// Identifies the task that owns `busy`, so a stopped or stale task cannot end a newer one.
    @ObservationIgnored private var operationID: UUID?
    @ObservationIgnored private var generation = UUID()
    /// Observed: the composer swaps Send for Stop on `isAnswering`.
    private var activeAnswerID: UUID?
    @ObservationIgnored private var started = false
    @ObservationIgnored var unlocked = false
    /// Observed: `canExport` reads it.
    var visits: [Visit] = []

    /// The honest photo line for iPhone and iPad (spec section 2): ordinary photos are checked
    /// on device for scene labels; only screenshots are counted without being read.
    public static let photoCopy = "Photos are checked on this iPhone for scene labels, such as beach or food. Nothing leaves the device and no photo is kept. Screenshots are counted only. Photos stored only in iCloud are skipped."
    public static let safariCopy = "iOS does not let apps read Safari history, so Pastport does not."
    public static let importedSafariCopy = "Safari history is available only from an export you chose. It stays in memory on this device and is cleared when you lock or leave."
    /// What iOS can read of Safari: nothing directly, or only the export the person chose.
    public var safariLine: String { importedHistoryActive ? Self.importedSafariCopy : Self.safariCopy }
    public static let offlineCopy = "Offline is fine. Timeline, Ask and screenshots run on this iPhone. Only Connected tools need a connection."
    public static let noTextFound = "No text found. Try a clearer screenshot."
    public static let unlockFailed = "Could not unlock. Nothing was read."
    static let photosClosed = "Photos are closed. Read activity when you choose."
    static let screenshotsClosed = "Add a screenshot of a booking or receipt. Its text is read on this device and emails, codes and card numbers are hidden."
    public static let appleModelName = AppleFoundation.displayName

    public init(
        history: (any HistorySource)?,
        importedHistory: ImportedHistorySource? = nil,
        photos: any PhotoLibraryReading = PhotoLibraryProvider(),
        screenshotReader: ScreenshotReader = ScreenshotReader(),
        authenticator: any Authenticating = DeviceAuthenticator(),
        timelineAnswerer: any TimelineAnswering = FoundationTimelineAnswerer(),
        localModels: LocalModels? = nil,
        appleIntelligenceReady: @escaping @Sendable () -> Bool = { AppleFoundation.isReady },
        skeptic: any SkepticReviewing = FoundationSkeptic(),
        historian: any HistorianNarrating = FoundationHistorian(),
        days: Int = 90) {
        self.days = days
        self.history = history
        self.importedHistory = importedHistory
        self.photos = photos
        self.screenshotReader = screenshotReader
        self.authenticator = authenticator
        self.timelineAnswerer = timelineAnswerer
        self.localModels = localModels
        self.appleIntelligenceReady = appleIntelligenceReady
        self.skeptic = skeptic
        self.historianNarrator = historian
        codex.attach { [weak self] in self?.mcpHistoryView }
    }

    /// What a connected coding agent may be shown, once the person approves: only the unlocked, retained
    /// history this session already read. Nil while locked or before a read.
    var mcpHistoryView: McpHistoryView? {
        guard !isLocked, historyLoaded, importedHistory == nil, !visits.isEmpty else { return nil }
        return McpHistoryView(visits: visits, windowDescription: "\(windowTitle) · \(visits.count) pages")
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

    /// What the "Open Timeline" App Intent does: show the Timeline tab on the locked screen.
    /// Anything already read is cleared and nothing is returned to the caller.
    public func openTimeline() {
        lockAndClear()
        tab = .trail
    }

    /// What the "Ask Pastport" App Intent does: show Ask on the locked screen with the question
    /// waiting. Nothing is read or answered until the person unlocks, and Siri gets nothing back.
    public func openAsk(question: String) {
        lockAndClear()
        tab = .ask
        let question = question.trimmingCharacters(in: .whitespacesAndNewlines)
        pendingQuestion = question.isEmpty ? nil : question
    }

    public func lockAndClear() {
        generation = UUID()
        operation?.cancel(); operation = nil; operationID = nil
        unlocked = false; busy = false; isLocked = true
        codex.revoke()
        importedHistory?.clear(); importedHistoryActive = false; importStatus = ""
        visits = []; movements = []; threads = []; travel = []; themes = []
        photoEvents = []; screenshots = []; turns = []; skepticReviews = [:]; historian = nil; input = ""; pendingQuestion = nil
        coverage = ""; profile = ""; journeyReceipt = nil
        sites = []; trackerSignals = []; historyLoaded = false
        historyFocus = .overview; recommendedFocuses = [.overview]; suggestedQuestions = []
        agentTrailStops = []; agentTrailStatus = ""; agentTrailRunning = false
        trail = .overview
        let oldJourney = journey; journey = nil
        activeAnswerID = nil
        Task { await oldJourney?.clear() }
        for state in sessionScoped.values { state.lockAndClear() }
        photoStatus = Self.photosClosed
        screenshotStatus = Self.screenshotsClosed
        status = "Locked. Cached history, photo activity, screenshots and answers cleared."
        contentID = UUID()
        #if DEBUG
        if demoMode { return }
        #endif
        authenticator.relock()
    }

    // MARK: Photos

    public func readPhotos() { unlock() }

    /// Authenticates, then asks for Photos access, then reads the window. The timeline unlocks
    /// when that read ends, even with nothing found; a failed authentication keeps it locked.
    public func unlock() {
        guard !busy else { return }
        #if DEBUG
        if demoMode { loadDemoPhotos(); isLocked = false; return }
        #endif
        let token = generation
        let since = days == 0 ? Date.distantPast : Date().addingTimeInterval(-Double(days) * 86400)
        busy = true
        let owner = UUID(); operationID = owner
        operation = Task { @MainActor in
            defer {
                if token == generation, operationID == owner {
                    busy = false; operationID = nil
                    askPendingQuestion()
                }
            }
            do {
                // Authentication precedes even the Photos permission prompt.
                let result = await authenticator.unlock(reason: "read your local photo activity", graceMinutes: 0)
                guard token == generation, !Task.isCancelled else { authenticator.relock(); return }
                guard result == .unlocked else { photoStatus = Self.unlockFailed; return }
                await photos.requestAccess()
                guard token == generation, !Task.isCancelled else { return }
                let photoRead = try await photos.read(since: since, limit: 500)
                guard token == generation, !Task.isCancelled else { return }
                photoEvents = PhotoEvents.cluster(photoRead.records)
                photoStatus = PhotoEvents.statusLine(for: photoRead)
                isLocked = false
            } catch is CancellationError {
            } catch let error as PhotoLibraryError {
                guard token == generation else { return }
                photoEvents = []; photoStatus = PhotoEvents.statusLine(for: error); isLocked = false
            } catch {
                guard token == generation else { return }
                photoEvents = []; photoStatus = "Photo activity could not be read. Try again after checking Photos access."
                isLocked = false
            }
        }
    }

    // MARK: Safari export (iPhone and iPad)

    /// Reads a Safari export ZIP the person chose. Face ID comes first and the file is opened only after it
    /// succeeds. A failure leaves what was on screen as it was and says why in `importStatus`; a success keeps the
    /// scrubbed visits in memory until the next lock.
    public func importSafariExport(from url: URL) {
        importSafariExport {
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            return try SafariExport.read(from: url)
        }
    }

    /// The same import for a file a Shortcut handed over as bytes. Face ID still comes first.
    public func importSafariExport(data: Data) {
        importSafariExport { try SafariExport.read(bytes: data) }
    }

    private func importSafariExport(_ read: @escaping @Sendable () throws -> SafariExportResult) {
        guard let importedHistory, !busy else { return }
        let token = generation
        busy = true
        let owner = UUID(); operationID = owner
        importStatus = ""
        operation = Task { @MainActor in
            var imported = false
            defer {
                if token == generation, operationID == owner {
                    busy = false; operationID = nil
                    if imported { loadTrail() }
                }
            }
            status = "Waiting for Face ID…"
            let result = await authenticator.unlock(reason: "import your Safari history export", graceMinutes: 0)
            guard token == generation, !Task.isCancelled else { authenticator.relock(); return }
            guard result == .unlocked else { importStatus = Self.unlockFailed; return }
            status = "Reading the export on this device…"
            let outcome: Result<SafariExportResult, SafariExportError> = await Task.detached {
                do { return .success(try read()) } catch let error as SafariExportError {
                    return .failure(error)
                } catch { return .failure(.notAnArchive) }
            }.value
            guard token == generation, !Task.isCancelled else { return }
            switch outcome {
            case .failure(let error):
                importStatus = error.description
            case .success(let export):
                importedHistory.load(export)
                importedHistoryActive = true
                unlocked = true; isLocked = false
                importStatus = "Imported. This stays in memory on this device until you lock or leave Pastport."
                imported = true
            }
        }
    }

    /// What the "Ask about a page" Shortcut does: show Ask on the locked screen with a question about the page's
    /// site waiting. Nothing is read, and nothing of the address except its host is kept.
    public func openAsk(aboutPage url: URL) {
        guard let question = SharedPage.question(for: url) else { openAsk(question: ""); return }
        openAsk(question: question)
    }

    /// The import was cancelled in the file picker; nothing was read.
    public func importCancelled() { importStatus = SafariExportError.cancelled.description }

    /// The file picker could not hand over a file.
    public func importFailed() { importStatus = SafariExportError.notAnArchive.description }

    /// Safari's export sheet could not be opened.
    public func exportSheetFailed() { importStatus = "Safari could not open its export sheet. Open Settings > Apps > Safari and choose Export Browsing Data." }

    /// After a successful unlock, asks the question Siri handed over. A failed unlock keeps it waiting.
    private func askPendingQuestion() {
        guard !isLocked, let question = pendingQuestion else { return }
        pendingQuestion = nil
        input = question
        ask()
    }

    // MARK: Screenshots

    /// Reads one screenshot the person picked. Only scrubbed text is kept; the image is not.
    public func addScreenshot(data: Data, name: String) {
        screenshotStatus = "Reading the screenshot on this device…"
        read(data, name: name, token: generation)
    }

    private func read(_ data: Data, name: String, token: UUID) {
        let reader = screenshotReader
        Task { @MainActor in
            do {
                let evidence = try await reader.read(imageData: data)
                guard token == generation else { return }
                guard !evidence.scrubbedLines.isEmpty else { screenshotStatus = Self.noTextFound; return }
                screenshots.append(AddedScreenshot(name: name, evidence: evidence))
                screenshotStatus = "Screenshot read · \(evidence.redactionCount) item\(evidence.redactionCount == 1 ? "" : "s") hidden"
            } catch {
                guard token == generation else { return }
                screenshotStatus = "That image could not be read."
            }
        }
    }

    /// Loads picked image data, then reads it. A lock while loading drops the result.
    public func addScreenshot(name: String, load: @escaping @Sendable () async -> Data?) {
        let token = generation
        screenshotStatus = "Reading the screenshot on this device…"
        Task { @MainActor in
            guard let data = await load(), token == generation else { return }
            read(data, name: name, token: token)
        }
    }

    public func removeScreenshot(_ id: AddedScreenshot.ID) {
        screenshots.removeAll { $0.id == id }
    }

    public var timelineEvidence: TimelineEvidence {
        TimelineEvidence(window: windowTitle, photoEvents: photoEvents, screenshots: screenshots,
                         historyAvailable: canReadHistory, trail: trail)
    }

    /// The cards for the open trail, built by code from what was read.
    public var evidenceCards: [EvidenceCard] {
        EvidenceCards.cards(for: trail, photoEvents: photoEvents, screenshots: screenshots, window: windowTitle)
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
        guard let history = activeHistory else { return nil }
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
        let owner = UUID(); operationID = owner
        operation = Task { @MainActor in
            defer {
                if token == generation, operationID == owner {
                    busy = false; operationID = nil
                    // A question handed over while locked (Siri, a shared page) is asked once the history is in.
                    if historyLoaded { askPendingQuestion() }
                }
            }
            codex.revoke()
            movements = []; threads = []; travel = []; themes = []; visits = []
            sites = []; trackerSignals = []; historyLoaded = false; turns = []; skepticReviews = [:]; historian = nil; journeyReceipt = nil
            agentTrailStops = []; agentTrailStatus = ""; agentTrailRunning = false
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
        let owner = UUID(); operationID = owner
        operation = Task { @MainActor in
            defer { if token == generation, operationID == owner { busy = false; operationID = nil } }
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

    /// Plans and executes a bounded sequence against this unlocked snapshot.
    public func buildAgentTrail() {
        guard historyLoaded, !visits.isEmpty, !busy else { return }
        let token = generation, owner = UUID()
        operationID = owner; busy = true; agentTrailRunning = true
        agentTrailStops = []; agentTrailStatus = "Planning a trail…"
        operation = Task { @MainActor in
            defer {
                if token == generation, operationID == owner {
                    busy = false; agentTrailRunning = false; operationID = nil; operation = nil
                }
            }
            let session = journey ?? HistoryJourney(visits: visits, scope: coverage)
            journey = session
            do {
                let plan = try await session.recommend("Plan a few distinct evidence trails to revisit.")
                guard token == generation, operationID == owner, !Task.isCancelled else { return }
                let focuses = Array(plan.focuses.filter { availableFocuses.contains($0) }.prefix(3))
                guard !focuses.isEmpty else { agentTrailStatus = "No supported trail was found in this window."; return }
                let planner = plan.usedModel ? "Apple Intelligence planned" : "Recorded evidence selected"
                for focus in focuses {
                    agentTrailStatus = "\(planner) \(focuses.count) stops · checking \(focus.title.lowercased())…"
                    let question = questions(for: focus).first ?? "Summarize retained history."
                    let answer = try await session.answer(question, focus: focus)
                    guard token == generation, operationID == owner, !Task.isCancelled else { return }
                    agentTrailStops.append(AgentTrailStop(focus: focus, answer: answer))
                }
                agentTrailStatus = "\(planner) \(agentTrailStops.count) stops · review the source evidence."
            } catch {
                guard token == generation, operationID == owner, !Task.isCancelled else { return }
                agentTrailStatus = "The trail could not finish. Completed stops remain available."
            }
        }
    }

    public func stopAgentTrail() {
        guard agentTrailRunning else { return }
        operation?.cancel(); operation = nil; operationID = nil
        busy = false; agentTrailRunning = false
        agentTrailStatus = "Stopped. Completed stops remain available."
        let oldJourney = journey; journey = nil
        Task { await oldJourney?.clear() }
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
        let turn = AskTurn(prompt: q, answer: "Preparing evidence…")
        turns.append(turn)
        activeAnswerID = turn.id
        let token = generation
        busy = true
        let owner = UUID(); operationID = owner
        operation = Task { @MainActor in
            defer { if token == generation, operationID == owner { busy = false; operationID = nil } }
            // Before history is read, a Mac with photos or screenshots asks the timeline instead.
            if canReadHistory, historyLoaded || timelineEvidence.isEmpty {
                await answerFromHistory(q, turnID: turn.id, token: token)
            } else {
                await answerFromTimeline(q, turnID: turn.id, token: token)
            }
        }
    }

    /// Tells the story of the read window as up to five chapters. Swift writes each chapter's facts and a plain
    /// sentence at once; when Apple Intelligence is ready, a model then writes each chapter's prose in turn, and
    /// a chapter keeps its plain sentence unless the prose passes `HistorianValidation`. Memory only; a lock drops it.
    public func tellStory() {
        guard historyLoaded, !visits.isEmpty, historian == nil else { return }
        let token = generation
        let snapshot = visits
        let narrator = historianNarrator
        let ready = appleIntelligenceReady()
        historian = HistorianStory(chapters: [], isRunning: true)
        Task { @MainActor in
            let chapters = await Task.detached { HistorianPlanner.chapters(from: snapshot) }.value
            guard token == generation else { return }
            historian = HistorianStory(chapters: chapters, isRunning: ready && !chapters.isEmpty)
            guard ready else { return }
            for index in chapters.indices {
                let facts = chapters[index].facts
                do {
                    let prose = try await boundedTask(timeout: .seconds(20), operation: {
                        try await narrator.narrate(facts: facts, voice: .archivist)
                    }, onTimeout: {})
                    guard token == generation else { return }
                    let text = prose.trimmingCharacters(in: .whitespacesAndNewlines)
                    if HistorianValidation.allows(text, facts: facts) {
                        historian?.chapters[index].narration = text
                        historian?.chapters[index].origin = .model
                    }
                } catch {
                    guard token == generation else { return }
                }
            }
            guard token == generation else { return }
            historian?.isRunning = false
        }
    }

    private static let answerBasisMarker = "\nSource evidence: "

    /// Challenges one finished answer against the recorded facts: code checks first, then, when Apple
    /// Intelligence is ready, a model review whose quotes are checked against the answer. The review stays in
    /// memory and is dropped by a lock; one is run per answer.
    public func challenge(_ turnID: AskTurn.ID) {
        guard let turn = turns.first(where: { $0.id == turnID }), turn.status == .answered,
              skepticReviews[turnID] == nil else { return }
        let parts = turn.answer.components(separatedBy: Self.answerBasisMarker)
        let answer = (parts.first ?? turn.answer).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !answer.isEmpty else { return }
        skepticReviews[turnID] = .checking
        let token = generation
        let question = turn.prompt
        let basis = parts.dropFirst().flatMap { $0.components(separatedBy: "\n") }
        let useHistory = canReadHistory && historyLoaded
        let timelineLines = timelineEvidence.lines
        let snapshot = visits
        let reviewer = skeptic
        let ready = appleIntelligenceReady()
        Task { @MainActor in
            let evidence: [String]
            if useHistory {
                // Any retained-history slice may have fed the answer, so every slice counts as a known fact.
                let slices = await Task.detached {
                    [.overview, .travel, .location, .research, .trackers].flatMap { intent in
                        AskWorkflow.evidence(for: intent, visits: snapshot).components(separatedBy: "\n")
                    }
                }.value
                evidence = basis + slices
            } else {
                evidence = basis + timelineLines
            }
            guard token == generation else { return }
            var findings = SkepticChecks.review(answer: answer, evidenceLines: evidence)
            var modelStatus = SkepticReview.ModelStatus.notRun
            if ready {
                do {
                    let proposed = try await boundedTask(timeout: .seconds(20), operation: {
                        try await reviewer.review(question: question, answer: answer, evidenceLines: evidence)
                    }, onTimeout: {})
                    guard token == generation else { return }
                    findings += SkepticChecks.accept(model: proposed, answer: answer, existing: findings)
                    modelStatus = .reviewed
                } catch {
                    guard token == generation else { return }
                    modelStatus = .failed
                }
            }
            guard token == generation else { return }
            skepticReviews[turnID] = .done(SkepticReview(findings: findings, model: modelStatus))
        }
    }

    /// Stops the answer in progress. The partial text stays, marked as stopped.
    public func stopAnswer() {
        guard let id = activeAnswerID else { return }
        activeAnswerID = nil
        operation?.cancel(); operation = nil; operationID = nil
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
        if let direct = HistoryFacts.answer(question: q, visits: visits) {
            activeAnswerID = nil
            update(turnID) { $0.answer = direct.text; $0.status = .answered; $0.note = "Counted from your history on this device" }
            status = "Answer ready"
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
                update(turnID) {
                    $0.answer = result.text; $0.toolsUsed = result.receipt.toolCalls
                    $0.matchingSources = result.matchingSources; $0.status = .answered
                    $0.note = result.origin == .model
                        ? "Apple Intelligence · on-device history evidence"
                        : "Recorded facts · Apple Intelligence answer unavailable"
                }
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
                    $0.evidenceKinds = progress.evidenceKinds
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
        input = starterQuestions.first ?? questions(for: historyFocus).first ?? ""
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
