import Darwin
import Foundation
import PastportKit
import Testing
@testable import PastportMac

private struct Approve: McpApproving {
    func decide(_ request: McpApprovalRequest) async -> McpApprovalDecision { .approve(lifetime: 60) }
}

/// A minimal client: one connection, lines out and in.
private final class Client {
    let fd: Int32
    init?(path: String) {
        fd = socket(AF_UNIX, SOCK_STREAM, 0)
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let capacity = MemoryLayout.size(ofValue: address.sun_path)
        withUnsafeMutableBytes(of: &address.sun_path) { buffer in
            _ = path.withCString { strncpy(buffer.baseAddress!.assumingMemoryBound(to: CChar.self), $0, capacity - 1) }
        }
        let ok = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        if ok != 0 { close(fd); return nil }
        var on: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
        var timeout = timeval(tv_sec: 5, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
    }

    func send(_ json: String) { let line = Array((json + "\n").utf8); _ = write(fd, line, line.count) }

    func line() -> String? {
        var bytes: [UInt8] = []
        var one: UInt8 = 0
        while read(fd, &one, 1) == 1 { if one == 0x0A { break }; bytes.append(one) }
        return bytes.isEmpty ? nil : String(decoding: bytes, as: UTF8.self)
    }
}

@Suite("MCP socket", .timeLimit(.minutes(1)))
struct McpSocketServerTests {
    private func run(_ body: (String, McpBroker) throws -> Void) throws {
        let path = "/tmp/pp-mcp-\(UUID().uuidString.prefix(8)).sock"
        let history = McpHistoryView(visits: [Visit(time: .now, title: "Paris guide", url: "https://guide.example/paris?x=secret")],
                                     windowDescription: "test window")
        let broker = McpBroker(source: { history }, approver: Approve())
        let server = McpSocketServer(broker: broker, path: path)
        try server.start()
        defer { server.stop() }
        try body(path, broker)
    }

    @Test("a client on the socket can initialize, list tools and, once approved, search with a scrubbed result")
    func endToEnd() throws {
        try run { path, _ in
            let client = try #require(Client(path: path))
            client.send(#"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","clientInfo":{"name":"codex"}}}"#)
            #expect(client.line()?.contains("\"pastport\"") == true)
            client.send(#"{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"pastport_search","arguments":{"query":"paris"}}}"#)
            let reply = try #require(client.line())
            #expect(reply.contains("guide.example") && reply.contains("\"isError\":false"))
            #expect(!reply.contains("secret") && !reply.contains("?x="))
            close(client.fd)
        }
    }

    @Test("the socket is private to the user, and stopping the server closes it and removes the file")
    func permissionsAndStop() throws {
        let path = "/tmp/pp-mcp-\(UUID().uuidString.prefix(8)).sock"
        let broker = McpBroker(source: { nil }, approver: Approve())
        let server = McpSocketServer(broker: broker, path: path)
        try server.start()
        var info = stat()
        #expect(stat(path, &info) == 0 && (info.st_mode & 0o077) == 0)
        let client = try #require(Client(path: path))
        server.stop()
        #expect(!FileManager.default.fileExists(atPath: path))
        client.send(#"{"jsonrpc":"2.0","id":1,"method":"ping"}"#)
        #expect(client.line() == nil, "an open connection is closed when the server stops")
        close(client.fd)
        #expect(Client(path: path) == nil)
    }

    @Test("a connection that sends a huge line without a newline is dropped")
    func oversizedLineIsDropped() throws {
        try run { path, _ in
            let client = try #require(Client(path: path))
            let junk = [UInt8](repeating: 0x41, count: 300 * 1024)
            var sent = 0
            while sent < junk.count { let n = write(client.fd, junk, junk.count - sent); if n <= 0 { break }; sent += n }
            #expect(client.line() == nil)
            close(client.fd)
        }
    }
}
