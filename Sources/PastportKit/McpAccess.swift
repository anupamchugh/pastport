import Foundation

// A consented, bounded way for a local coding agent (Codex) to ask Pastport about history.
//
// Nothing here reads Safari. The broker is handed a closure that returns the visits of the session the
// person already unlocked, or nil while Pastport is locked. A tool call that needs history waits for the
// person to approve that one scope for that one connection; approval ends on expiry, lock, denial,
// cancellation or disconnect. Results are small, scrubbed and carry no query strings or times of day.

public enum McpScope: String, CaseIterable, Sendable, Hashable {
    case search = "history.search"
    case topSites = "history.top_sites"

    public var summary: String {
        switch self {
        case .search: "search the pages in your unlocked history (titles, sites and days; no query strings)"
        case .topSites: "see which sites you visit most in your unlocked history window (site names and counts)"
        }
    }
}

/// Who is asking. `declaredName` is whatever the client says about itself and is not trusted;
/// `executable` and `launchedBy` are read by the operating system from the connecting process when it can be.
public struct McpClientIdentity: Sendable, Equatable {
    public var declaredName: String
    public var executable: String?
    /// The program that started the connecting process, such as Codex starting the bridge.
    public var launchedBy: String?

    public init(declaredName: String = "an unnamed client", executable: String? = nil, launchedBy: String? = nil) {
        self.declaredName = Self.clean(declaredName)
        self.executable = executable
        self.launchedBy = launchedBy
    }

    /// What the approval prompt shows: the claim, then what the system says is really connecting.
    public var label: String {
        func program(_ path: String?) -> String? { path.map { URL(filePath: $0).lastPathComponent } }
        var parts = [declaredName]
        if let name = program(executable), name.caseInsensitiveCompare(declaredName) != .orderedSame {
            parts.append("running as \(name)")
        }
        if let name = program(launchedBy) { parts.append("started by \(name)") }
        return parts.count == 1 ? declaredName : "\(declaredName) (\(parts.dropFirst().joined(separator: ", ")))"
    }

    static func clean(_ text: String) -> String {
        let scalars = text.unicodeScalars.filter { $0.value >= 0x20 && $0.value != 0x7F }
        let cleaned = String(String.UnicodeScalarView(scalars)).trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? "an unnamed client" : String(cleaned.prefix(60))
    }
}

public struct McpApprovalRequest: Sendable, Identifiable {
    public let id = UUID()
    public let client: McpClientIdentity
    public let scope: McpScope
    /// The longest access the broker will grant for this request.
    public let maxLifetime: TimeInterval
}

public enum McpApprovalDecision: Sendable, Equatable {
    case approve(lifetime: TimeInterval)
    case deny
}

/// Asks the person. The implementation must return promptly when its task is cancelled, and must never
/// answer on the person's behalf.
public protocol McpApproving: Sendable {
    func decide(_ request: McpApprovalRequest) async -> McpApprovalDecision
}

/// A window onto the unlocked session. `windowDescription` says what the visits cover.
public struct McpHistoryView: Sendable {
    public let visits: [Visit]
    public let windowDescription: String

    public init(visits: [Visit], windowDescription: String) {
        self.visits = visits
        self.windowDescription = windowDescription
    }
}

public struct McpToolResult: Sendable, Equatable {
    public let text: String
    public let structured: JSONValue?
    public let isError: Bool
}

public actor McpBroker {
    public struct Settings: Sendable {
        public var grantLifetime: TimeInterval = 15 * 60
        public var maxLifetime: TimeInterval = 60 * 60
        public var denialCooldown: TimeInterval = 5 * 60
        public var callsPerMinute = 20
        public var maxResults = 10
        public init() {}
    }

    private enum Refusal: Error { case locked, denied, ended, rateLimited }

    private struct PendingKey: Hashable { let connection: UUID; let scope: McpScope }

    private let settings: Settings
    private let source: @Sendable () async -> McpHistoryView?
    private let approver: any McpApproving
    private let now: @Sendable () -> Date
    private var live = Set<UUID>()
    private var grants: [UUID: [McpScope: Date]] = [:]
    private var denials: [UUID: [McpScope: Date]] = [:]
    private var calls: [UUID: [Date]] = [:]
    private var pending: [PendingKey: Task<McpApprovalDecision, Never>] = [:]
    private var epoch = 0

    public init(settings: Settings = Settings(),
                source: @escaping @Sendable () async -> McpHistoryView?,
                approver: any McpApproving,
                now: @escaping @Sendable () -> Date = { Date() }) {
        self.settings = settings
        self.source = source
        self.approver = approver
        self.now = now
    }

    // MARK: Connections

    func register(_ connection: UUID) { live.insert(connection) }

    /// A connection ended. Its approvals and any question still open for it end with it.
    public func disconnect(_ connection: UUID) {
        live.remove(connection)
        grants[connection] = nil
        denials[connection] = nil
        calls[connection] = nil
        for key in pending.keys where key.connection == connection {
            pending[key]?.cancel(); pending[key] = nil
        }
    }

    /// Pastport locked: every approval ends and every open question is withdrawn.
    public func revokeAll() {
        epoch += 1
        grants = [:]; denials = [:]; calls = [:]
        pending.values.forEach { $0.cancel() }
        pending = [:]
    }

    /// Scopes this connection holds right now, with when each ends.
    public func activeGrants(for connection: UUID) -> [McpScope: Date] {
        let current = now()
        return (grants[connection] ?? [:]).filter { $0.value > current }
    }

    // MARK: Tools

    public static let tools: [JSONValue] = [
        tool("pastport_status",
             "Say whether Pastport is unlocked and which access the person has approved for this connection. Never reads history and never asks the person anything.",
             properties: [:], required: []),
        tool("pastport_search",
             "Search pages in the person's unlocked Safari history. Needs the person's approval of history.search. Returns up to 10 pages with a title, site, short path and day; no query strings or times. A visit only shows a page was opened, not that it was read or acted on.",
             properties: ["query": .object(["type": .string("string"), "description": .string("Words that must all appear in the page title, site or path. 2 to 80 characters.")]),
                          "limit": .object(["type": .string("integer"), "description": .string("How many pages, 1 to 10. Default 5.")])],
             required: ["query"]),
        tool("pastport_top_sites",
             "List the sites visited most in the person's unlocked history window, with visit counts. Needs the person's approval of history.top_sites.",
             properties: ["limit": .object(["type": .string("integer"), "description": .string("How many sites, 1 to 10. Default 5.")])],
             required: []),
    ]

    private static func tool(_ name: String, _ description: String,
                                         properties: [String: JSONValue], required: [String]) -> JSONValue {
        .object([
            "name": .string(name),
            "description": .string(description),
            "inputSchema": .object([
                "type": .string("object"),
                "properties": .object(properties),
                "required": .array(required.map(JSONValue.string)),
                "additionalProperties": .bool(false),
            ]),
            "annotations": .object(["readOnlyHint": .bool(true), "openWorldHint": .bool(false)]),
        ])
    }

    public func callTool(connection: UUID, identity: McpClientIdentity, name: String,
                         arguments: JSONValue?) async -> McpToolResult {
        register(connection)
        do {
            switch name {
            case "pastport_status":
                return await status(connection: connection)
            case "pastport_search":
                let query = arguments?["query"]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                guard (2...80).contains(query.count) else {
                    return .failure("query must be 2 to 80 characters.")
                }
                let view = try await authorize(connection: connection, identity: identity, scope: .search)
                return search(view, query: query, limit: limit(arguments))
            case "pastport_top_sites":
                let view = try await authorize(connection: connection, identity: identity, scope: .topSites)
                return topSites(view, limit: limit(arguments))
            default:
                return .failure("Unknown tool.")
            }
        } catch let refusal as Refusal {
            switch refusal {
            case .locked: return .failure("Pastport is locked or not running. Ask the person to open Pastport, unlock their history and turn on the Codex connection.")
            case .denied: return .failure("The person declined this request. Do not retry; ask them to approve it in Pastport if they want to.")
            case .ended: return .failure("Access ended: Pastport was locked, the question was withdrawn, or this connection closed.")
            case .rateLimited: return .failure("Too many requests. Wait a minute.")
            }
        } catch {
            return .failure("Access ended: the request was cancelled.")
        }
    }

    private func limit(_ arguments: JSONValue?) -> Int {
        min(max(arguments?["limit"]?.intValue ?? 5, 1), settings.maxResults)
    }

    // MARK: Approval

    private func authorize(connection: UUID, identity: McpClientIdentity, scope: McpScope) async throws -> McpHistoryView {
        guard await source() != nil else { throw Refusal.locked }
        let current = now()
        if let until = denials[connection]?[scope], until > current { throw Refusal.denied }
        if (grants[connection]?[scope] ?? .distantPast) <= current {
            try await askPerson(connection: connection, identity: identity, scope: scope)
        }
        // Re-read after any wait: the lock may have landed while the question was open.
        guard live.contains(connection), let view = await source() else { throw Refusal.locked }
        let moment = now()
        guard (grants[connection]?[scope] ?? .distantPast) > moment else { throw Refusal.ended }
        let recent = (calls[connection] ?? []).filter { moment.timeIntervalSince($0) < 60 }
        guard recent.count < settings.callsPerMinute else { throw Refusal.rateLimited }
        calls[connection] = recent + [moment]
        return view
    }

    private func askPerson(connection: UUID, identity: McpClientIdentity, scope: McpScope) async throws {
        let key = PendingKey(connection: connection, scope: scope)
        let started = epoch
        let task: Task<McpApprovalDecision, Never>
        if let existing = pending[key] { task = existing } else {
            let request = McpApprovalRequest(client: identity, scope: scope, maxLifetime: settings.maxLifetime)
            let approver = approver
            task = Task { await approver.decide(request) }
            pending[key] = task
        }
        let decision = await withTaskCancellationHandler { await task.value } onCancel: { task.cancel() }
        if pending[key] == task { pending[key] = nil }
        if Task.isCancelled { throw Refusal.ended }
        guard live.contains(connection), epoch == started else { throw Refusal.ended }
        switch decision {
        case .approve(let lifetime):
            let seconds = min(max(lifetime, 1), settings.maxLifetime)
            grants[connection, default: [:]][scope] = now().addingTimeInterval(seconds)
            denials[connection]?[scope] = nil
        case .deny:
            denials[connection, default: [:]][scope] = now().addingTimeInterval(settings.denialCooldown)
            throw Refusal.denied
        }
    }

    // MARK: Results

    private func status(connection: UUID) async -> McpToolResult {
        let unlocked = await source() != nil
        let formatter = ISO8601DateFormatter()
        let granted = activeGrants(for: connection)
        let state: JSONValue = .object([
            "state": .string(unlocked ? "ready" : "locked"),
            "approved": .object(Dictionary(uniqueKeysWithValues: granted.map { ($0.key.rawValue, JSONValue.string(formatter.string(from: $0.value))) })),
            "scopes": .array(McpScope.allCases.map { .string($0.rawValue) }),
        ])
        let line = unlocked
            ? "Pastport is unlocked. Approved for this connection: \(granted.isEmpty ? "nothing yet" : granted.keys.map(\.rawValue).sorted().joined(separator: ", ")). A request outside that asks the person first."
            : "Pastport is locked. The person must open Pastport and unlock their history before anything can be asked."
        return McpToolResult(text: line, structured: state, isError: false)
    }

    private func search(_ view: McpHistoryView, query: String, limit: Int) -> McpToolResult {
        let words = query.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
        guard !words.isEmpty else { return .failure("query must contain letters or numbers.") }
        var seen = Set<String>()
        var rows: [JSONValue] = []
        for visit in view.visits.sorted(by: { $0.time > $1.time }) {
            let page = McpSanitizer.page(visit)
            guard !SensitiveTopics.matches(visit.title + " " + visit.cleanURL) else { continue }
            let haystack = (visit.title + " " + page.site + " " + page.path).lowercased()
            guard words.allSatisfy({ haystack.contains($0) }), seen.insert(visit.cleanURL).inserted else { continue }
            rows.append(.object(["title": .string(page.title), "site": .string(page.site),
                                 "path": .string(page.path), "day": .string(McpSanitizer.day(visit.time))]))
            if rows.count == limit { break }
        }
        let structured: JSONValue = .object(["window": .string(view.windowDescription), "pages": .array(rows),
                                             "note": .string("A visit shows a page was opened, not that it was read, bought or acted on.")])
        let text = rows.isEmpty
            ? "No pages matched in \(view.windowDescription)."
            : McpSanitizer.render(structured)
        return McpToolResult(text: text, structured: structured, isError: false)
    }

    private func topSites(_ view: McpHistoryView, limit: Int) -> McpToolResult {
        var counts: [String: Int] = [:]
        for visit in view.visits where !SensitiveTopics.matches(visit.title + " " + visit.cleanURL) {
            counts[visit.host, default: 0] += 1
        }
        let top = counts.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }.prefix(limit)
        let structured: JSONValue = .object([
            "window": .string(view.windowDescription),
            "sites": .array(top.map { .object(["site": .string($0.key), "visits": .int($0.value)]) }),
        ])
        return McpToolResult(text: McpSanitizer.render(structured), structured: structured, isError: false)
    }
}

extension McpToolResult {
    fileprivate static func failure(_ text: String) -> McpToolResult {
        McpToolResult(text: text, structured: nil, isError: true)
    }
}

/// What may leave Pastport about a page: a scrubbed, shortened title, the site, a short path made of
/// plain segments, and the day. Never a query string, fragment, credentials or a time of day.
enum McpSanitizer {
    struct Page { let title: String; let site: String; let path: String }

    static func page(_ visit: Visit) -> Page {
        let title = ScreenshotScrubber.scrub([visit.title]).scrubbedLines.joined(separator: " ")
        let components = URLComponents(string: visit.cleanURL)
        let segments = (components?.path ?? "").split(separator: "/").prefix(3).map { segment -> String in
            let text = String(segment)
            let hasDigit = text.contains { $0.isNumber }
            // Long mixed segments are usually tokens, ids or invitations.
            if text.count > 40 || (text.count > 20 && hasDigit) || text.contains("@") { return "…" }
            return text
        }
        return Page(title: String(title.prefix(120)), site: visit.host, path: segments.isEmpty ? "/" : "/" + segments.joined(separator: "/"))
    }

    static func day(_ date: Date) -> String {
        date.formatted(.iso8601.year().month().day())
    }

    static func render(_ value: JSONValue) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return (try? String(data: encoder.encode(value), encoding: .utf8)) ?? ""
    }
}

// MARK: JSON-RPC

public enum JSONValue: Codable, Hashable, Sendable {
    case null
    case bool(Bool)
    case int(Int)
    case double(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    public init(from decoder: any Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let v = try? c.decode(Bool.self) { self = .bool(v) }
        else if let v = try? c.decode(Int.self) { self = .int(v) }
        else if let v = try? c.decode(Double.self) { self = .double(v) }
        else if let v = try? c.decode(String.self) { self = .string(v) }
        else if let v = try? c.decode([JSONValue].self) { self = .array(v) }
        else if let v = try? c.decode([String: JSONValue].self) { self = .object(v) }
        else { throw DecodingError.dataCorruptedError(in: c, debugDescription: "Not JSON") }
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .null: try c.encodeNil()
        case .bool(let v): try c.encode(v)
        case .int(let v): try c.encode(v)
        case .double(let v): try c.encode(v)
        case .string(let v): try c.encode(v)
        case .array(let v): try c.encode(v)
        case .object(let v): try c.encode(v)
        }
    }

    public subscript(key: String) -> JSONValue? {
        if case .object(let o) = self { return o[key] }
        return nil
    }

    public var stringValue: String? { if case .string(let v) = self { v } else { nil } }

    public var intValue: Int? {
        switch self {
        case .int(let v): v
        case .double(let v) where v == v.rounded() && abs(v) < 1e9: Int(v)
        default: nil
        }
    }
}

/// One client connection. Lines in, lines out; it holds no history and talks only to the broker.
public final class McpSession: @unchecked Sendable {
    public static let supportedProtocols = ["2025-06-18", "2025-03-26", "2024-11-05"]

    public let id = UUID()
    private let broker: McpBroker
    private let lock = NSLock()
    private var identity: McpClientIdentity
    private var initialized = false
    private var inflight: [JSONValue: Task<Void, Never>] = [:]
    private var closed = false

    public init(broker: McpBroker, executable: String? = nil, launchedBy: String? = nil) {
        self.broker = broker
        self.identity = McpClientIdentity(executable: executable, launchedBy: launchedBy)
    }

    /// Handles one JSON-RPC message. Replies, if any, go to `send` as one JSON object (no newline).
    public func receive(_ data: Data, send: @escaping @Sendable (Data) -> Void) {
        guard let message = try? JSONDecoder().decode(JSONValue.self, from: data), case .object = message else {
            return reply(.null, error: -32700, "Parse error", send)
        }
        let id = message["id"]
        guard let method = message["method"]?.stringValue else {
            if id != nil { reply(id ?? .null, error: -32600, "Invalid request", send) }
            return
        }
        guard let id else { notification(method, message["params"]); return }
        let task = Task { [self] in
            let response = await respond(method: method, params: message["params"], id: id)
            let cancelled = lock.withLock { () -> Bool in
                inflight[id] = nil
                return closed || Task.isCancelled
            }
            if !cancelled, let encoded = try? JSONEncoder().encode(response) { send(encoded) }
        }
        lock.withLock { if !closed { inflight[id] = task } else { task.cancel() } }
    }

    /// The connection ended: cancel open requests and end every approval it held.
    public func close() {
        let tasks = lock.withLock { () -> [Task<Void, Never>] in
            closed = true
            defer { inflight = [:] }
            return Array(inflight.values)
        }
        tasks.forEach { $0.cancel() }
        let broker = broker, id = id
        Task { await broker.disconnect(id) }
    }

    private func notification(_ method: String, _ params: JSONValue?) {
        guard method == "notifications/cancelled", let target = params?["requestId"] else { return }
        let task = lock.withLock { inflight.removeValue(forKey: target) }
        task?.cancel()
    }

    private func respond(method: String, params: JSONValue?, id: JSONValue) async -> JSONValue {
        switch method {
        case "initialize":
            let name = params?["clientInfo"]?["name"]?.stringValue ?? ""
            lock.withLock {
                identity = McpClientIdentity(declaredName: name, executable: identity.executable, launchedBy: identity.launchedBy)
                initialized = true
            }
            let asked = params?["protocolVersion"]?.stringValue ?? ""
            let version = Self.supportedProtocols.contains(asked) ? asked : Self.supportedProtocols[0]
            return result(id, .object([
                "protocolVersion": .string(version),
                "capabilities": .object(["tools": .object(["listChanged": .bool(false)])]),
                "serverInfo": .object(["name": .string("pastport"), "version": .string("1")]),
                "instructions": .string("Pastport answers only after the person approves each kind of access in the Pastport app. Results are small and scrubbed. Do not ask for more than you need."),
            ]))
        case "ping":
            return result(id, .object([:]))
        case "tools/list", "tools/call":
            guard lock.withLock({ initialized }) else { return error(id, -32002, "Send initialize first.") }
            if method == "tools/list" { return result(id, .object(["tools": .array(McpBroker.tools)])) }
            guard let name = params?["name"]?.stringValue else { return error(id, -32602, "Missing tool name.") }
            let who = lock.withLock { identity }
            let outcome = await broker.callTool(connection: self.id, identity: who, name: name, arguments: params?["arguments"])
            var content: [String: JSONValue] = [
                "content": .array([.object(["type": .string("text"), "text": .string(outcome.text)])]),
                "isError": .bool(outcome.isError),
            ]
            if let structured = outcome.structured { content["structuredContent"] = structured }
            return result(id, .object(content))
        default:
            return error(id, -32601, "Method not found.")
        }
    }

    private func result(_ id: JSONValue, _ value: JSONValue) -> JSONValue {
        .object(["jsonrpc": .string("2.0"), "id": id, "result": value])
    }

    private func error(_ id: JSONValue, _ code: Int, _ message: String) -> JSONValue {
        .object(["jsonrpc": .string("2.0"), "id": id, "error": .object(["code": .int(code), "message": .string(message)])])
    }

    private func reply(_ id: JSONValue, error code: Int, _ message: String, _ send: @Sendable (Data) -> Void) {
        if let data = try? JSONEncoder().encode(error(id, code, message)) { send(data) }
    }
}
