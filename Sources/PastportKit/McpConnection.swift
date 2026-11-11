import Foundation
import Observation

/// The Mac app's side of the Codex connection: an off-by-default switch, the questions waiting for the
/// person, and the broker that enforces what was approved. The switch is per session and is not saved,
/// so Pastport always starts with the connection off.
@MainActor @Observable
public final class McpConnection {
    public static let grantChoices: [(title: String, seconds: TimeInterval)] = [
        ("Allow for 15 minutes", 15 * 60), ("Allow for 1 hour", 60 * 60),
    ]

    public internal(set) var enabled = false
    public internal(set) var pending: [McpApprovalRequest] = []
    /// Set when the listener could not start; shown beside the switch.
    public internal(set) var problem: String?

    @ObservationIgnored public let broker: McpBroker
    /// Starts or stops the listener. Installed by the Mac app; Kit has no sockets.
    @ObservationIgnored public var serveControl: (@MainActor (Bool) throws -> Void)?
    /// Called when a question arrives, so the app can come to the front.
    @ObservationIgnored public var onRequest: (@MainActor () -> Void)?
    @ObservationIgnored private let history = HistoryBox()
    @ObservationIgnored private var waiters: [UUID: CheckedContinuation<McpApprovalDecision, Never>] = [:]

    public init(settings: McpBroker.Settings = McpBroker.Settings()) {
        let box = history
        let relay = Relay()
        broker = McpBroker(settings: settings, source: { await box.read() }, approver: relay)
        relay.owner = self
    }

    /// Where the unlocked history comes from. The closure returns nil while Pastport is locked.
    public func attach(history provider: @escaping @MainActor () -> McpHistoryView?) { history.provider = provider }

    public func setEnabled(_ on: Bool) {
        guard on != enabled else { return }
        problem = nil
        if on {
            do { try serveControl?(true) } catch {
                problem = "Could not start the connection."
                return
            }
            enabled = true
        } else {
            enabled = false
            revoke()
            try? serveControl?(false)
        }
    }

    public func respond(to request: McpApprovalRequest, _ decision: McpApprovalDecision) {
        resolve(request.id, decision)
    }

    /// Lock, a new window, or switching off: every approval ends and every open question is withdrawn.
    public func revoke() {
        for id in Array(waiters.keys) { resolve(id, .deny) }
        let broker = broker
        Task { await broker.revokeAll() }
    }

    fileprivate func ask(_ request: McpApprovalRequest) async -> McpApprovalDecision {
        guard enabled else { return .deny }
        return await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<McpApprovalDecision, Never>) in
                if Task.isCancelled { continuation.resume(returning: .deny); return }
                pending.append(request)
                waiters[request.id] = continuation
                onRequest?()
            }
        } onCancel: {
            Task { @MainActor [weak self] in self?.resolve(request.id, .deny) }
        }
    }

    private func resolve(_ id: UUID, _ decision: McpApprovalDecision) {
        pending.removeAll { $0.id == id }
        waiters.removeValue(forKey: id)?.resume(returning: decision)
    }

    @MainActor private final class HistoryBox {
        var provider: (@MainActor () -> McpHistoryView?)?
        func read() -> McpHistoryView? { provider?() }
    }

    private final class Relay: McpApproving, @unchecked Sendable {
        weak var owner: McpConnection?
        func decide(_ request: McpApprovalRequest) async -> McpApprovalDecision {
            guard let owner = owner else { return .deny }
            return await owner.ask(request)
        }
    }
}
