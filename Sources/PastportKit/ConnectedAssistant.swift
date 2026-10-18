import Combine
import Foundation
import FoundationLabCore
import FoundationModels
import FoundationModelsKit
import FoundationModelsTools

#if canImport(HealthKit)
import HealthKit
#endif

/// The user-visible record of one model-requested connected-tool call.
public struct ConnectedToolReceipt: Identifiable, Hashable, Sendable {
    public let id: UUID
    public let toolName: String
    public let arguments: String
    public let status: Status
    public let elapsedSeconds: Double?
    public let timestamp: Date

    public enum Status: String, Hashable, Sendable {
        case completed
        case denied
        case failed
    }

    public init(
        id: UUID = UUID(),
        toolName: String,
        arguments: String,
        status: Status,
        elapsedSeconds: Double? = nil,
        timestamp: Date = Date()
    ) {
        self.id = id
        self.toolName = toolName
        self.arguments = arguments
        self.status = status
        self.elapsedSeconds = elapsedSeconds
        self.timestamp = timestamp
    }
}

/// The exact request shown before a connected tool is allowed to run.
public struct ConnectedToolApprovalRequest: Identifiable, Hashable, Sendable {
    public let id: UUID
    public let generation: UUID
    public let toolName: String
    public let arguments: String
    public let destination: String
    public let service: String

    public init(
        id: UUID = UUID(),
        generation: UUID,
        toolName: String,
        arguments: String,
        destination: String,
        service: String
    ) {
        self.id = id
        self.generation = generation
        self.toolName = toolName
        self.arguments = arguments
        self.destination = destination
        self.service = service
    }
}

public enum ConnectedToolApprovalError: Error, LocalizedError, Sendable, Equatable {
    case denied
    case cancelled
    case staleGeneration

    public var errorDescription: String? {
        switch self {
        case .denied:
            "The connected tool request was denied."
        case .cancelled:
            "The connected tool request was cancelled."
        case .staleGeneration:
            "The connected tool request expired when the assistant session changed."
        }
    }
}

/// Policy shared by the UI, adapters, and tests. It intentionally has no I/O.
public enum ConnectedAssistantPolicy {
    public static let maximumSelectedTools = 3

    public static func canSelect(_ tool: FoundationLabBuiltInTool, alongside selected: [FoundationLabBuiltInTool]) -> Bool {
        selected.contains(tool) || selected.count < maximumSelectedTools
    }

    public static func permitsContactAction(_ action: String) -> Bool {
        ["search", "read"].contains(action.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
    }

    public static func permitsMusicAction(_ action: String) -> Bool {
        ["search", "nowplaying"].contains(action.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
    }

    public static var healthIsAvailable: Bool {
        #if canImport(HealthKit)
        HKHealthStore.isHealthDataAvailable()
        #else
        false
        #endif
    }

    public static func isAvailable(_ tool: FoundationLabBuiltInTool) -> Bool {
        tool != .health || healthIsAvailable
    }
}

/// Owns one pending app decision. Tool calls suspend here until the user acts.
public actor ConnectedToolApprovalCoordinator {
    public typealias RequestHandler = @MainActor @Sendable (ConnectedToolApprovalRequest) -> Void

    private var continuations: [UUID: CheckedContinuation<Bool, Never>] = [:]
    private var requests: [UUID: ConnectedToolApprovalRequest] = [:]
    private var onRequest: RequestHandler?

    public init(onRequest: RequestHandler? = nil) {
        self.onRequest = onRequest
    }

    public func setRequestHandler(_ handler: RequestHandler?) {
        onRequest = handler
    }

    public func request(_ request: ConnectedToolApprovalRequest) async throws -> Bool {
        try Task.checkCancellation()
        let approved = await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
                continuations[request.id] = continuation
                requests[request.id] = request
                if let onRequest {
                    Task { @MainActor in onRequest(request) }
                }
            }
        } onCancel: {
            Task { await self.cancel(request.id) }
        }
        try Task.checkCancellation()
        return approved
    }

    public func resolve(_ requestID: UUID, approved: Bool) {
        guard let continuation = continuations.removeValue(forKey: requestID) else { return }
        requests.removeValue(forKey: requestID)
        continuation.resume(returning: approved)
    }

    public func cancel(_ requestID: UUID) {
        resolve(requestID, approved: false)
    }

    public func cancelAll() {
        let pending = continuations
        continuations.removeAll()
        requests.removeAll()
        pending.values.forEach { $0.resume(returning: false) }
    }
}

struct ApprovedTool<Base: Tool>: Tool where Base.Arguments: RuntimeCompatibleGenerable {
    let base: Base
    let approval: ConnectedToolApprovalCoordinator
    let generationProvider: @MainActor @Sendable () -> UUID
    let destination: String
    let service: String
    let receipt: @MainActor @Sendable (ConnectedToolReceipt) -> Void

    var name: String { base.name }
    var description: String { base.description }
    var parameters: GenerationSchema { base.parameters }

    func call(arguments: Base.Arguments) async throws -> some PromptRepresentable {
        let argumentJSON = arguments.generatedContent.jsonString
        let requestGeneration = await MainActor.run { generationProvider() }
        let request = ConnectedToolApprovalRequest(
            generation: requestGeneration,
            toolName: name,
            arguments: argumentJSON,
            destination: destination,
            service: service
        )
        guard try await approval.request(request) else {
            await MainActor.run {
                guard generationProvider() == requestGeneration else { return }
                receipt(ConnectedToolReceipt(
                    toolName: name,
                    arguments: argumentJSON,
                    status: .denied
                ))
            }
            throw ConnectedToolApprovalError.denied
        }
        guard await MainActor.run(body: { generationProvider() == requestGeneration }) else {
            throw ConnectedToolApprovalError.staleGeneration
        }
        try Task.checkCancellation()
        let start = ContinuousClock.now
        do {
            let result = try await base.call(arguments: arguments)
            let elapsed = start.duration(to: .now)
            await MainActor.run {
                guard generationProvider() == requestGeneration else { return }
                receipt(ConnectedToolReceipt(
                    toolName: name,
                    arguments: argumentJSON,
                    status: .completed,
                    elapsedSeconds: elapsed.secondsAsDouble
                ))
            }
            return result
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            let elapsed = start.duration(to: .now)
            await MainActor.run {
                guard generationProvider() == requestGeneration else { return }
                receipt(ConnectedToolReceipt(
                    toolName: name,
                    arguments: argumentJSON,
                    status: .failed,
                    elapsedSeconds: elapsed.secondsAsDouble
                ))
            }
            throw error
        }
    }
}

private struct ReadOnlyContactsTool: Tool {
    let approval: ConnectedToolApprovalCoordinator
    let generationProvider: @MainActor @Sendable () -> UUID
    let receipt: @MainActor @Sendable (ConnectedToolReceipt) -> Void

    let name = "readContacts"
    let description = "Search or read contacts after explicit app approval; creating contacts is unavailable"
    typealias Arguments = ContactsTool.Arguments

    func call(arguments: Arguments) async throws -> GeneratedContent {
        guard ConnectedAssistantPolicy.permitsContactAction(arguments.action) else {
            throw ConnectedToolApprovalError.denied
        }
        let argumentJSON = arguments.generatedContent.jsonString
        let requestGeneration = await MainActor.run { generationProvider() }
        let request = ConnectedToolApprovalRequest(
            generation: requestGeneration,
            toolName: name,
            arguments: argumentJSON,
            destination: "Contacts",
            service: "Contacts"
        )
        guard try await approval.request(request) else {
            await MainActor.run {
                guard generationProvider() == requestGeneration else { return }
                receipt(ConnectedToolReceipt(toolName: name, arguments: argumentJSON, status: .denied))
            }
            throw ConnectedToolApprovalError.denied
        }
        guard await MainActor.run(body: { generationProvider() == requestGeneration }) else {
            throw ConnectedToolApprovalError.staleGeneration
        }
        try Task.checkCancellation()
        let start = ContinuousClock.now
        do {
            let result = try await ContactsTool().call(arguments: arguments)
            let elapsed = start.duration(to: .now)
            await MainActor.run {
                guard generationProvider() == requestGeneration else { return }
                receipt(ConnectedToolReceipt(
                    toolName: name, arguments: argumentJSON, status: .completed,
                    elapsedSeconds: elapsed.secondsAsDouble
                ))
            }
            return result
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            let elapsed = start.duration(to: .now)
            await MainActor.run {
                guard generationProvider() == requestGeneration else { return }
                receipt(ConnectedToolReceipt(
                    toolName: name, arguments: argumentJSON, status: .failed,
                    elapsedSeconds: elapsed.secondsAsDouble
                ))
            }
            throw error
        }
    }
}

private struct ReadOnlyMusicTool: Tool {
    let approval: ConnectedToolApprovalCoordinator
    let generationProvider: @MainActor @Sendable () -> UUID
    let receipt: @MainActor @Sendable (ConnectedToolReceipt) -> Void

    let name = "readMusic"
    let description = "Search Apple Music or read now playing after explicit app approval; playback controls are unavailable"
    typealias Arguments = MusicTool.Arguments

    func call(arguments: Arguments) async throws -> some PromptRepresentable {
        guard ConnectedAssistantPolicy.permitsMusicAction(arguments.action) else {
            throw ConnectedToolApprovalError.denied
        }
        return try await ApprovedTool(
            base: MusicTool(), approval: approval, generationProvider: generationProvider,
            destination: "Apple Music", service: "MusicKit",
            receipt: receipt
        ).call(arguments: arguments)
    }
}

private extension Duration {
    var secondsAsDouble: Double {
        let components = components
        return Double(components.seconds) + Double(components.attoseconds) / 1e18
    }
}

/// Optional, source-separated connected-tools assistant for Pastport.
@MainActor
public final class ConnectedAssistant: ObservableObject {
    public struct Message: Identifiable, Hashable, Sendable {
        public let id: UUID
        public let role: Role
        public var text: String

        public enum Role: String, Hashable, Sendable {
            case user
            case assistant
        }

        public init(id: UUID = UUID(), role: Role, text: String) {
            self.id = id
            self.role = role
            self.text = text
        }
    }

    @Published public var draft = ""
    @Published public private(set) var messages: [Message] = []
    @Published public private(set) var selectedTools: [FoundationLabBuiltInTool] = []
    @Published public private(set) var toolReceipts: [ConnectedToolReceipt] = []
    @Published public private(set) var pendingApproval: ConnectedToolApprovalRequest?
    @Published public private(set) var status = "Connected tools are off until you choose them."
    @Published public private(set) var isLoading = false
    @Published public private(set) var currentTokenCount = 0
    @Published public private(set) var currentTokenUsage: ModelTokenUsage?
    @Published public private(set) var lastTurnUsage: ModelTokenUsage?
    @Published public private(set) var maxContextSize: Int
    @Published public private(set) var sessionCount = 1
    @Published public private(set) var generation = UUID()

    private lazy var approval: ConnectedToolApprovalCoordinator = ConnectedToolApprovalCoordinator(
        onRequest: { [weak self] request in
            guard let self else { return }
            guard self.generation == request.generation else {
                Task { await self.approval.cancel(request.id) }
                return
            }
            self.pendingApproval = request
        }
    )
    private var engine: FoundationModelConversationEngine
    private var operation: Task<Void, Never>?
    private var usageBeforeTurn: ModelTokenUsage?

    public init() {
        let defaultContextSize = 4_096
        maxContextSize = defaultContextSize
        let configuration = FoundationModelConversationConfiguration(
            baseInstructions: Self.instructions,
            summaryInstructions: "Preserve the user's connected-tool conversation accurately.",
            summaryPromptPreamble: "Summarize this connected-tools conversation without adding data.",
            conversationUserLabel: "User:",
            conversationAssistantLabel: "Assistant:",
            continuationNote: "Continue this connected-tools conversation.",
            modelUseCase: .general,
            guardrails: .default,
            enableSlidingWindow: false,
            defaultMaxContextSize: defaultContextSize
        )
        engine = FoundationModelConversationEngine(configuration: configuration)
        engine.onStateChange = { [weak self] in self?.syncState() }
        syncState()
        Task { @MainActor [weak self] in
            self?.refreshContextSize()
        }
    }

    public var contextSummary: String {
        guard let currentTokenUsage else {
            return "Session usage unavailable · context limit \(maxContextSize) · session \(sessionCount)"
        }
        let usage = "\(currentTokenUsage.scope.rawValue), \(currentTokenUsage.measurement.rawValue)"
        return "Session usage \(currentTokenUsage.totalTokenCount) tokens · context limit \(maxContextSize) · \(usage) · session \(sessionCount)"
    }

    public func toggleTool(_ tool: FoundationLabBuiltInTool) {
        guard ConnectedAssistantPolicy.isAvailable(tool) else {
            status = "Health is unavailable on this Mac and remains disabled."
            return
        }
        guard ConnectedAssistantPolicy.canSelect(tool, alongside: selectedTools) else {
            status = "Choose at most \(ConnectedAssistantPolicy.maximumSelectedTools) connected tools for this small-model session."
            return
        }
        if let index = selectedTools.firstIndex(of: tool) {
            selectedTools.remove(at: index)
        } else {
            selectedTools.append(tool)
        }
        generation = UUID()
        operation?.cancel()
        engine.cancelActiveResponse()
        isLoading = false
        Task { await approval.cancelAll() }
        pendingApproval = nil
        engine.rebuild(tools: makeTools(for: selectedTools))
        status = "Tool selection changed; conversation restarted. No Safari history is attached."
        syncState()
    }

    public func send() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isLoading else { return }
        draft = ""
        let token = generation
        usageBeforeTurn = currentTokenUsage
        messages.append(Message(role: .user, text: text))
        messages.append(Message(role: .assistant, text: ""))
        isLoading = true
        status = "Generating with connected tools…"
        operation = Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                if self.generation == token { self.isLoading = false }
            }
            do {
                let response = try await self.engine.sendStreamingMessage(text) { [weak self] partial in
                    guard let self, self.generation == token, !Task.isCancelled else { return }
                    guard let index = self.messages.lastIndex(where: { $0.role == .assistant }) else { return }
                    self.messages[index].text = partial
                }
                guard self.generation == token else { return }
                if let index = self.messages.lastIndex(where: { $0.role == .assistant }) {
                    self.messages[index].text = response
                }
                self.lastTurnUsage = Self.usageDelta(from: self.usageBeforeTurn, to: self.currentTokenUsage)
                self.status = "Connected tools ready. No Safari history is attached."
                self.syncState()
            } catch is CancellationError {
            } catch {
                guard self.generation == token else { return }
                if let index = self.messages.lastIndex(where: { $0.role == .assistant }) {
                    self.messages[index].text = "The connected-tools request could not finish: \(error.localizedDescription)"
                }
                self.status = "Connected-tools request failed; no result was invented."
            }
        }
    }

    public func cancel() {
        generation = UUID()
        operation?.cancel()
        operation = nil
        engine.cancelActiveResponse()
        pendingApproval = nil
        Task { await approval.cancelAll() }
        isLoading = false
        status = "Connected-tools request cancelled."
    }

    public func allowPending() {
        guard let pendingApproval else { return }
        guard pendingApproval.generation == generation else {
            self.pendingApproval = nil
            Task { await approval.cancel(pendingApproval.id) }
            return
        }
        self.pendingApproval = nil
        Task { await approval.resolve(pendingApproval.id, approved: true) }
    }

    public func denyPending() {
        guard let pendingApproval else { return }
        self.pendingApproval = nil
        Task { await approval.resolve(pendingApproval.id, approved: false) }
        status = "Request denied; the connected service was not called."
    }

    public func clear() {
        generation = UUID()
        operation?.cancel()
        operation = nil
        engine.cancelActiveResponse()
        Task { await approval.cancelAll() }
        pendingApproval = nil
        messages = []
        toolReceipts = []
        lastTurnUsage = nil
        usageBeforeTurn = nil
        draft = ""
        isLoading = false
        engine.clear()
        status = "Connected-tools conversation cleared. No Safari history is attached."
        syncState()
    }

    public func lockAndClear() {
        clear()
        status = "Locked. Connected-tools conversation and approvals cleared."
    }
}

private extension ConnectedAssistant {
    static let instructions = """
    You are Pastport's optional connected-tools assistant. Be concise and truthful.
    This session has no Safari history, browsing evidence, photos, contacts, calendar, reminders,
    health, location, or music data unless an explicitly selected connected tool is approved for
    this exact call. Never invent a tool result. Explain when a request was denied or unavailable.
    """

    func syncState() {
        currentTokenCount = engine.currentTokenCount
        currentTokenUsage = engine.currentTokenUsage
        maxContextSize = engine.maxContextSize
        sessionCount = engine.sessionCount
    }

    static func usageDelta(from before: ModelTokenUsage?, to after: ModelTokenUsage?) -> ModelTokenUsage? {
        guard let after else { return nil }
        guard let before else {
            return ModelTokenUsage(
                input: after.input,
                output: after.output,
                measurement: after.measurement,
                scope: .response
            )
        }
        let input = ModelTokenUsage.Input(
            totalTokenCount: max(0, after.input.totalTokenCount - before.input.totalTokenCount)
        )
        let output: ModelTokenUsage.Output? = after.output.map { current in
            let previous = before.output?.totalTokenCount ?? 0
            let previousReasoning = before.output?.reasoningTokenCount ?? 0
            let reasoning = current.reasoningTokenCount.map { max(0, $0 - previousReasoning) }
            return ModelTokenUsage.Output(
                totalTokenCount: max(0, current.totalTokenCount - previous),
                reasoningTokenCount: reasoning
            )
        }
        return ModelTokenUsage(
            input: input,
            output: output,
            measurement: after.measurement,
            scope: .response
        )
    }

    func refreshContextSize() {
        #if compiler(>=6.3)
        engine.setMaxContextSize(SystemLanguageModel.default.contextSize)
        #endif
        syncState()
    }

    func appendReceipt(_ receipt: ConnectedToolReceipt) {
        toolReceipts.append(receipt)
    }

    func makeTools(for tools: [FoundationLabBuiltInTool]) -> [any Tool] {
        let generationProvider: @MainActor @Sendable () -> UUID = { [weak self] in
            self?.generation ?? UUID()
        }
        let receiptSink: @MainActor @Sendable (ConnectedToolReceipt) -> Void = { [weak self] receipt in
            self?.appendReceipt(receipt)
        }
        return tools.flatMap { tool -> [any Tool] in
            switch tool {
            case .weather:
                return [approved(WeatherTool(), destination: "Weather", service: "Open-Meteo + MapKit", generationProvider: generationProvider)]
            case .web:
                return [approved(Search1WebSearchTool(), destination: "Web", service: "Search1API", generationProvider: generationProvider)]
            case .contacts:
                return [ReadOnlyContactsTool(approval: approval, generationProvider: generationProvider, receipt: receiptSink)]
            case .calendar:
                return FoundationLabBuiltInTool.calendarToolsForPastport(
                    approval: approval, generationProvider: generationProvider, receipt: receiptSink
                )
            case .reminders:
                return FoundationLabBuiltInTool.reminderToolsForPastport(
                    approval: approval, generationProvider: generationProvider, receipt: receiptSink
                )
            case .location:
                return [approved(FoundationModelsTools.LocationTool(), destination: "Location", service: "Location + MapKit", generationProvider: generationProvider)]
            case .health:
                guard ConnectedAssistantPolicy.healthIsAvailable else { return [] }
                return [approved(HealthTool(), destination: "Health", service: "HealthKit", generationProvider: generationProvider)]
            case .music:
                return [ReadOnlyMusicTool(approval: approval, generationProvider: generationProvider, receipt: receiptSink)]
            case .webMetadata:
                return [approved(WebMetadataTool(), destination: "Web metadata", service: "URLSession", generationProvider: generationProvider)]
            @unknown default:
                return []
            }
        }
    }

    func approved<Base: Tool>(
        _ base: Base,
        destination: String,
        service: String,
        generationProvider: @escaping @MainActor @Sendable () -> UUID
    ) -> any Tool where Base.Arguments: RuntimeCompatibleGenerable {
        ApprovedTool(
            base: base, approval: approval, generationProvider: generationProvider,
            destination: destination, service: service,
            receipt: { [weak self] receipt in self?.appendReceipt(receipt) }
        )
    }
}

private extension FoundationLabBuiltInTool {
    @MainActor
    static func calendarToolsForPastport(
        approval: ConnectedToolApprovalCoordinator,
        generationProvider: @escaping @MainActor @Sendable () -> UUID,
        receipt: @escaping @MainActor @Sendable (ConnectedToolReceipt) -> Void
    ) -> [any Tool] {
        let service = EventKitCalendarService()
        return [ApprovedTool(
            base: CalendarReadTool(service: service), approval: approval, generationProvider: generationProvider,
            destination: "Calendar", service: "EventKit", receipt: receipt
        )]
    }

    @MainActor
    static func reminderToolsForPastport(
        approval: ConnectedToolApprovalCoordinator,
        generationProvider: @escaping @MainActor @Sendable () -> UUID,
        receipt: @escaping @MainActor @Sendable (ConnectedToolReceipt) -> Void
    ) -> [any Tool] {
        let service = EventKitRemindersService()
        return [ApprovedTool(
            base: RemindersReadTool(service: service), approval: approval, generationProvider: generationProvider,
            destination: "Reminders", service: "EventKit", receipt: receipt
        )]
    }
}
