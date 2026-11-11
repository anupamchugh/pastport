import Foundation
import Testing
@testable import PastportKit

/// Answers approval requests from a script, and records what it was asked.
private final class ScriptedApprover: McpApproving, @unchecked Sendable {
    private let lock = NSLock()
    private var asked: [McpApprovalRequest] = []
    private let decision: McpApprovalDecision?

    /// nil: never answers until cancelled.
    init(_ decision: McpApprovalDecision?) { self.decision = decision }

    var requests: [McpApprovalRequest] { lock.withLock { asked } }

    func decide(_ request: McpApprovalRequest) async -> McpApprovalDecision {
        lock.withLock { asked.append(request) }
        if let decision { return decision }
        while !Task.isCancelled { try? await Task.sleep(for: .milliseconds(5)) }
        return .deny
    }
}

private final class Clock: @unchecked Sendable {
    private let lock = NSLock()
    private var current = Date(timeIntervalSince1970: 1_800_000_000)
    var date: Date { lock.withLock { current } }
    func advance(_ seconds: TimeInterval) { lock.withLock { current = current.addingTimeInterval(seconds) } }
}

private final class Lockable: @unchecked Sendable {
    private let lock = NSLock()
    private var unlocked = true
    var isUnlocked: Bool { lock.withLock { unlocked } }
    func set(_ value: Bool) { lock.withLock { unlocked = value } }
}

private let day = Date(timeIntervalSince1970: 1_799_000_000)   // 3 Jan 2027, fictional

private let history = McpHistoryView(visits: [
    Visit(time: day, title: "Paris museum pass", url: "https://guide.example/paris/passes?session=SECRET&email=me@example.com#frag"),
    Visit(time: day.addingTimeInterval(-3_600), title: "Paris restaurants", url: "https://guide.example/paris/food"),
    Visit(time: day.addingTimeInterval(-7_200), title: "Clinic referral form", url: "https://health.example/clinic/referral"),
    Visit(time: day.addingTimeInterval(-9_000), title: "Invite", url: "https://app.example/join/9f8e7d6c5b4a39281706f5e4d3c2b1a0"),
    Visit(time: day.addingTimeInterval(-10_000), title: "Contact me@example.com about card 4111 1111 1111 1111", url: "https://mail.example/inbox"),
], windowDescription: "last 30 days · 5 visits")

private func makeBroker(approver: ScriptedApprover, clock: Clock = Clock(), lock: Lockable = Lockable(),
                        settings: McpBroker.Settings = .init()) -> McpBroker {
    McpBroker(settings: settings, source: { lock.isUnlocked ? history : nil }, approver: approver, now: { clock.date })
}

private let codex = McpClientIdentity(declaredName: "codex", executable: "/usr/local/bin/codex")

private func args(_ pairs: [String: JSONValue]) -> JSONValue { .object(pairs) }

@Suite("MCP access", .timeLimit(.minutes(1)))
struct McpAccessTests {
    @Test("history is never read before the person approves, and a denial is final for the cooldown")
    func denialReadsNothing() async {
        let approver = ScriptedApprover(.deny)
        let clock = Clock()
        let broker = makeBroker(approver: approver, clock: clock)
        let id = UUID()
        let first = await broker.callTool(connection: id, identity: codex, name: "pastport_search", arguments: args(["query": .string("paris")]))
        #expect(first.isError && first.structured == nil && !first.text.contains("guide.example"))
        // A retry inside the cooldown is refused without asking again.
        let second = await broker.callTool(connection: id, identity: codex, name: "pastport_search", arguments: args(["query": .string("paris")]))
        #expect(second.isError && approver.requests.count == 1)
        // After the cooldown the person is asked again.
        clock.advance(6 * 60)
        _ = await broker.callTool(connection: id, identity: codex, name: "pastport_search", arguments: args(["query": .string("paris")]))
        #expect(approver.requests.count == 2)
    }

    @Test("approval is per scope: search does not grant top sites")
    func approvalIsPerScope() async {
        let approver = ScriptedApprover(.approve(lifetime: 600))
        let broker = makeBroker(approver: approver)
        let id = UUID()
        _ = await broker.callTool(connection: id, identity: codex, name: "pastport_search", arguments: args(["query": .string("paris")]))
        _ = await broker.callTool(connection: id, identity: codex, name: "pastport_search", arguments: args(["query": .string("food")]))
        #expect(approver.requests.map(\.scope) == [.search])
        _ = await broker.callTool(connection: id, identity: codex, name: "pastport_top_sites", arguments: nil)
        #expect(approver.requests.map(\.scope) == [.search, .topSites])
    }

    @Test("approval is per connection: a second client is asked, and cannot borrow the first's grant")
    func approvalIsPerConnection() async {
        let approver = ScriptedApprover(.approve(lifetime: 600))
        let broker = makeBroker(approver: approver)
        let a = UUID(), b = UUID()
        _ = await broker.callTool(connection: a, identity: codex, name: "pastport_top_sites", arguments: nil)
        let other = McpClientIdentity(declaredName: "codex", executable: "/tmp/not-codex")
        _ = await broker.callTool(connection: b, identity: other, name: "pastport_top_sites", arguments: nil)
        #expect(approver.requests.count == 2)
        #expect(approver.requests[1].client.label.contains("not-codex"), "the real program is shown, not only the claimed name")
    }

    @Test("an approval expires, and a longer lifetime than the cap is cut to the cap")
    func approvalExpires() async {
        let approver = ScriptedApprover(.approve(lifetime: 10_000_000))
        let clock = Clock()
        var settings = McpBroker.Settings(); settings.maxLifetime = 600
        let broker = makeBroker(approver: approver, clock: clock, settings: settings)
        let id = UUID()
        _ = await broker.callTool(connection: id, identity: codex, name: "pastport_top_sites", arguments: nil)
        clock.advance(599)
        _ = await broker.callTool(connection: id, identity: codex, name: "pastport_top_sites", arguments: nil)
        #expect(approver.requests.count == 1)
        clock.advance(2)
        _ = await broker.callTool(connection: id, identity: codex, name: "pastport_top_sites", arguments: nil)
        #expect(approver.requests.count == 2)
    }

    @Test("locking ends approvals and withdraws a question that is still open")
    func lockEndsAccess() async throws {
        let lock = Lockable()
        let approver = ScriptedApprover(.approve(lifetime: 600))
        let broker = makeBroker(approver: approver, lock: lock)
        let id = UUID()
        let granted = await broker.callTool(connection: id, identity: codex, name: "pastport_top_sites", arguments: nil)
        #expect(!granted.isError)
        lock.set(false)
        await broker.revokeAll()
        let locked = await broker.callTool(connection: id, identity: codex, name: "pastport_top_sites", arguments: nil)
        #expect(locked.isError && locked.structured == nil)
        // Unlocking again does not bring the old approval back.
        lock.set(true)
        _ = await broker.callTool(connection: id, identity: codex, name: "pastport_top_sites", arguments: nil)
        #expect(approver.requests.count == 2)

        // A question open at the moment of the lock yields nothing, even if answered "approve" later.
        let waiting = ScriptedApprover(nil)
        let broker2 = makeBroker(approver: waiting)
        let call = Task { await broker2.callTool(connection: UUID(), identity: codex, name: "pastport_search", arguments: args(["query": .string("paris")])) }
        while waiting.requests.isEmpty { try await Task.sleep(for: .milliseconds(5)) }
        await broker2.revokeAll()
        let result = await call.value
        #expect(result.isError && result.structured == nil)
    }

    @Test("a closed connection withdraws its open question and drops its grants")
    func disconnectEndsAccess() async throws {
        let waiting = ScriptedApprover(nil)
        let broker = makeBroker(approver: waiting)
        let id = UUID()
        let call = Task { await broker.callTool(connection: id, identity: codex, name: "pastport_top_sites", arguments: nil) }
        while waiting.requests.isEmpty { try await Task.sleep(for: .milliseconds(5)) }
        await broker.disconnect(id)
        #expect((await call.value).isError)
        #expect(await broker.activeGrants(for: id).isEmpty)
    }

    @Test("cancelling the request withdraws the question")
    func cancellationEndsTheQuestion() async throws {
        let waiting = ScriptedApprover(nil)
        let broker = makeBroker(approver: waiting)
        let call = Task { await broker.callTool(connection: UUID(), identity: codex, name: "pastport_top_sites", arguments: nil) }
        while waiting.requests.isEmpty { try await Task.sleep(for: .milliseconds(5)) }
        call.cancel()
        let result = await call.value
        #expect(result.isError && result.structured == nil)
    }

    @Test("two simultaneous calls for one scope raise one question")
    func oneQuestionPerScope() async throws {
        let approver = ScriptedApprover(.approve(lifetime: 600))
        let broker = makeBroker(approver: approver)
        let id = UUID()
        async let a = broker.callTool(connection: id, identity: codex, name: "pastport_top_sites", arguments: nil)
        async let b = broker.callTool(connection: id, identity: codex, name: "pastport_top_sites", arguments: nil)
        let results = await [a, b]
        #expect(results.allSatisfy { !$0.isError })
        #expect(approver.requests.count == 1)
    }

    @Test("results carry no query string, fragment, address, card number, time of day or sensitive topic")
    func resultsAreScrubbed() async throws {
        let broker = makeBroker(approver: ScriptedApprover(.approve(lifetime: 600)))
        let id = UUID()
        let search = await broker.callTool(connection: id, identity: codex, name: "pastport_search", arguments: args(["query": .string("paris")]))
        #expect(!search.isError)
        let all = await broker.callTool(connection: id, identity: codex, name: "pastport_search", arguments: args(["query": .string("example"), "limit": .int(50)]))
        for text in [search.text, all.text] {
            for leak in ["SECRET", "session=", "#frag", "me@example.com", "4111", "?"] { #expect(!text.contains(leak), "leaked \(leak)") }
            #expect(!text.contains("T1") && !text.contains(":00"), "no time of day")
        }
        // The sensitive page is withheld, the long token segment is hidden, the other pages are present.
        #expect(!all.text.contains("clinic") && !all.text.contains("Clinic"))
        #expect(!all.text.contains("9f8e7d6c"))
        #expect(all.text.contains("guide.example") && all.text.contains("2027-01-03"))
        // Counts in top sites also leave out the sensitive page.
        let sites = await broker.callTool(connection: id, identity: codex, name: "pastport_top_sites", arguments: nil)
        #expect(!sites.text.contains("health.example"))
    }

    @Test("input is bounded: short and over-long queries are refused before anything is asked")
    func queriesAreBounded() async {
        let approver = ScriptedApprover(.approve(lifetime: 600))
        let broker = makeBroker(approver: approver)
        let id = UUID()
        for query in ["", "a", String(repeating: "x", count: 81)] {
            let r = await broker.callTool(connection: id, identity: codex, name: "pastport_search", arguments: args(["query": .string(query)]))
            #expect(r.isError)
        }
        let unknown = await broker.callTool(connection: id, identity: codex, name: "pastport_read_file", arguments: args(["path": .string("/etc/passwd")]))
        #expect(unknown.isError && approver.requests.isEmpty)
    }

    @Test("a client cannot call without limit: too many calls a minute are refused")
    func callsAreRateLimited() async {
        var settings = McpBroker.Settings(); settings.callsPerMinute = 3
        let broker = makeBroker(approver: ScriptedApprover(.approve(lifetime: 600)), settings: settings)
        let id = UUID()
        var errors = 0
        for _ in 0..<5 { if (await broker.callTool(connection: id, identity: codex, name: "pastport_top_sites", arguments: nil)).isError { errors += 1 } }
        #expect(errors == 2)
    }

    @Test("status needs no approval and never asks")
    func statusNeverAsks() async {
        let approver = ScriptedApprover(.deny)
        let broker = makeBroker(approver: approver)
        let r = await broker.callTool(connection: UUID(), identity: codex, name: "pastport_status", arguments: nil)
        #expect(!r.isError && approver.requests.isEmpty && r.structured?["state"]?.stringValue == "ready")
    }

    @Test("no tool offers writing, files, network or commands; every tool is read-only and closed")
    func toolListIsSmall() {
        let names = McpBroker.tools.compactMap { $0["name"]?.stringValue }
        #expect(names == ["pastport_status", "pastport_search", "pastport_top_sites"])
        for tool in McpBroker.tools {
            #expect(tool["annotations"]?["readOnlyHint"] == .bool(true))
            #expect(tool["annotations"]?["openWorldHint"] == .bool(false))
            #expect(tool["inputSchema"]?["additionalProperties"] == .bool(false))
        }
    }
}

@Suite("MCP session", .timeLimit(.minutes(1)))
struct McpSessionTests {
    private final class Outbox: @unchecked Sendable {
        private let lock = NSLock()
        private var items: [JSONValue] = []
        func add(_ data: Data) { if let v = try? JSONDecoder().decode(JSONValue.self, from: data) { lock.withLock { items.append(v) } } }
        var all: [JSONValue] { lock.withLock { items } }
        func reply(id: Int) -> JSONValue? { all.first { $0["id"] == .int(id) } }
    }

    private func line(_ object: [String: JSONValue]) -> Data { try! JSONEncoder().encode(JSONValue.object(object)) }

    private func waitFor(_ outbox: Outbox, id: Int) async throws -> JSONValue {
        for _ in 0..<1_000 { if let r = outbox.reply(id: id) { return r }; try await Task.sleep(for: .milliseconds(5)) }
        throw CancellationError()
    }

    @Test("the client must initialize first; then tools are listed and a call returns scrubbed content")
    func handshakeThenCall() async throws {
        let broker = makeBroker(approver: ScriptedApprover(.approve(lifetime: 600)))
        let session = McpSession(broker: broker, executable: "/usr/local/bin/codex")
        let out = Outbox()
        session.receive(line(["jsonrpc": .string("2.0"), "id": .int(1), "method": .string("tools/list")]), send: out.add)
        #expect(try await waitFor(out, id: 1)["error"] != nil)

        session.receive(line(["jsonrpc": .string("2.0"), "id": .int(2), "method": .string("initialize"),
                              "params": .object(["protocolVersion": .string("2025-06-18"), "clientInfo": .object(["name": .string("codex")])])]), send: out.add)
        let initialized = try await waitFor(out, id: 2)
        #expect(initialized["result"]?["serverInfo"]?["name"]?.stringValue == "pastport")
        #expect(initialized["result"]?["protocolVersion"]?.stringValue == "2025-06-18")

        session.receive(line(["jsonrpc": .string("2.0"), "id": .int(3), "method": .string("tools/list")]), send: out.add)
        guard case .array(let tools)? = try await waitFor(out, id: 3)["result"]?["tools"] else { Issue.record("no tools"); return }
        #expect(tools.count == 3)

        session.receive(line(["jsonrpc": .string("2.0"), "id": .int(4), "method": .string("tools/call"),
                              "params": .object(["name": .string("pastport_top_sites"), "arguments": .object([:])])]), send: out.add)
        let called = try await waitFor(out, id: 4)
        #expect(called["result"]?["isError"] == .bool(false))
        #expect(called["result"]?["structuredContent"]?["sites"] != nil)
        session.close()
    }

    @Test("a notifications/cancelled message withdraws the question and the call answers nothing")
    func clientCancellation() async throws {
        let waiting = ScriptedApprover(nil)
        let broker = makeBroker(approver: waiting)
        let session = McpSession(broker: broker)
        let out = Outbox()
        session.receive(line(["jsonrpc": .string("2.0"), "id": .int(1), "method": .string("initialize"), "params": .object([:])]), send: out.add)
        _ = try await waitFor(out, id: 1)
        session.receive(line(["jsonrpc": .string("2.0"), "id": .int(2), "method": .string("tools/call"),
                              "params": .object(["name": .string("pastport_top_sites")])]), send: out.add)
        while waiting.requests.isEmpty { try await Task.sleep(for: .milliseconds(5)) }
        session.receive(line(["jsonrpc": .string("2.0"), "method": .string("notifications/cancelled"), "params": .object(["requestId": .int(2)])]), send: out.add)
        try await Task.sleep(for: .milliseconds(200))
        #expect(out.reply(id: 2) == nil)
        session.close()
    }

    @Test("closing the session ends its approvals; junk and unknown methods get an error, not a crash")
    func closeAndJunk() async throws {
        let broker = makeBroker(approver: ScriptedApprover(.approve(lifetime: 600)))
        let session = McpSession(broker: broker)
        let out = Outbox()
        session.receive(Data("not json".utf8), send: out.add)
        #expect(out.all.first?["error"]?["code"] == .int(-32700))
        session.receive(line(["jsonrpc": .string("2.0"), "id": .int(9), "method": .string("resources/read")]), send: out.add)
        #expect(try await waitFor(out, id: 9)["error"]?["code"] == .int(-32601))
        session.receive(line(["jsonrpc": .string("2.0"), "id": .int(1), "method": .string("initialize"), "params": .object([:])]), send: out.add)
        _ = try await waitFor(out, id: 1)
        session.receive(line(["jsonrpc": .string("2.0"), "id": .int(2), "method": .string("tools/call"),
                              "params": .object(["name": .string("pastport_top_sites")])]), send: out.add)
        _ = try await waitFor(out, id: 2)
        #expect(await !broker.activeGrants(for: session.id).isEmpty)
        session.close()
        for _ in 0..<200 where await !broker.activeGrants(for: session.id).isEmpty { try await Task.sleep(for: .milliseconds(5)) }
        #expect(await broker.activeGrants(for: session.id).isEmpty)
    }
}
