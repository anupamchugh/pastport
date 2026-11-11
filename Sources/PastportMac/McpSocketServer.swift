import Darwin
import Foundation
import PastportKit

/// Where the Pastport app listens for the `pastport mcp` bridge. The folder is private to the person.
public enum McpSocket {
    public static var path: String {
        URL.applicationSupportDirectory.appending(path: "Pastport/mcp.sock").path
    }
}

public enum McpSocketError: Error { case unavailable }

/// A Unix-domain socket that only the same user can open. Each accepted connection becomes one
/// `McpSession`; lines in, lines out. Nothing is read from Safari here.
public final class McpSocketServer: @unchecked Sendable {
    private let broker: McpBroker
    private let path: String
    private let queue = DispatchQueue(label: "pastport.mcp.accept")
    private let lock = NSLock()
    private var listener: DispatchSourceRead?
    private var clients: [Int32: McpSession] = [:]
    static let maxClients = 4
    static let maxLine = 256 * 1024

    public init(broker: McpBroker, path: String = McpSocket.path) {
        self.broker = broker
        self.path = path
    }

    public func start() throws {
        lock.lock(); defer { lock.unlock() }
        guard listener == nil else { return }
        let directory = URL(filePath: path).deletingLastPathComponent().path
        try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        chmod(directory, 0o700)
        unlink(path)
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw McpSocketError.unavailable }
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let capacity = MemoryLayout.size(ofValue: address.sun_path)
        guard path.utf8.count < capacity else { close(fd); throw McpSocketError.unavailable }
        withUnsafeMutableBytes(of: &address.sun_path) { buffer in
            _ = path.withCString { strncpy(buffer.baseAddress!.assumingMemoryBound(to: CChar.self), $0, capacity - 1) }
        }
        let bound = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        guard bound == 0, chmod(path, 0o600) == 0, listen(fd, 4) == 0 else { close(fd); unlink(path); throw McpSocketError.unavailable }
        _ = fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) | O_NONBLOCK)
        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
        source.setEventHandler { [weak self] in self?.acceptPending(on: fd) }
        source.setCancelHandler { close(fd) }
        listener = source
        source.resume()
    }

    /// Stops listening and ends every connection, which ends every approval they held.
    public func stop() {
        lock.lock()
        let source = listener; listener = nil
        let open = clients; clients = [:]
        lock.unlock()
        source?.cancel()
        unlink(path)
        for (fd, session) in open { shutdown(fd, SHUT_RDWR); session.close() }
    }

    private func acceptPending(on listenerFD: Int32) {
        while true {
            let fd = accept(listenerFD, nil, nil)
            if fd < 0 { return }
            _ = fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) & ~O_NONBLOCK)
            Self.noSigPipe(fd)
            var uid: uid_t = 0, gid: gid_t = 0
            guard getpeereid(fd, &uid, &gid) == 0, uid == getuid() else { close(fd); continue }
            let identity = Self.peer(of: fd)
            let session = McpSession(broker: broker, executable: identity.executable, launchedBy: identity.launchedBy)
            // Checked and registered together, so a connection accepted while stop() runs is never kept.
            lock.lock()
            let accepted = listener != nil && clients.count < Self.maxClients
            if accepted { clients[fd] = session }
            lock.unlock()
            guard accepted else { close(fd); continue }
            Thread.detachNewThread { [weak self] in self?.serve(fd: fd, session: session) }
        }
    }

    private func serve(fd: Int32, session: McpSession) {
        let writer = NSLock()
        let send: @Sendable (Data) -> Void = { data in
            var line = data; line.append(0x0A)
            writer.lock(); defer { writer.unlock() }
            line.withUnsafeBytes { raw in
                var offset = 0
                while offset < raw.count {
                    let n = write(fd, raw.baseAddress! + offset, raw.count - offset)
                    if n <= 0 { return }
                    offset += n
                }
            }
        }
        var buffer = Data()
        var chunk = [UInt8](repeating: 0, count: 16 * 1024)
        reading: while true {
            let n = read(fd, &chunk, chunk.count)
            if n <= 0 { break }
            buffer.append(chunk, count: n)
            while let newline = buffer.firstIndex(of: 0x0A) {
                let line = buffer[buffer.startIndex..<newline]
                buffer.removeSubrange(buffer.startIndex...newline)
                if !line.isEmpty { session.receive(Data(line), send: send) }
            }
            if buffer.count > Self.maxLine { break reading }
        }
        lock.lock(); let known = clients.removeValue(forKey: fd) != nil; lock.unlock()
        session.close()
        if known { close(fd) }
    }

    /// A write to a client that has gone must fail with an error, not end the app with SIGPIPE.
    static func noSigPipe(_ fd: Int32) {
        var on: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
    }

    /// The connecting process and the program that started it, read from the kernel, not from the client.
    static func peer(of fd: Int32) -> (executable: String?, launchedBy: String?) {
        var pid: pid_t = 0
        var size = socklen_t(MemoryLayout<pid_t>.size)
        guard getsockopt(fd, SOL_LOCAL, LOCAL_PEERPID, &pid, &size) == 0, pid > 0 else { return (nil, nil) }
        return (executablePath(pid), parent(of: pid).flatMap(executablePath))
    }

    private static func executablePath(_ pid: pid_t) -> String? {
        var buffer = [CChar](repeating: 0, count: 4 * 1024)
        guard proc_pidpath(pid, &buffer, UInt32(buffer.count)) > 0 else { return nil }
        return String(cString: buffer)
    }

    private static func parent(of pid: pid_t) -> pid_t? {
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size, info.pbi_ppid > 1 else { return nil }
        return pid_t(info.pbi_ppid)
    }
}

/// `pastport mcp`: what Codex launches. It copies lines between Codex's pipes and the Pastport app's
/// socket. If the app is not running or the connection is off, it still answers, with a clear refusal.
public enum McpBridge {
    public static func run(path: String = McpSocket.path) -> Never {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let capacity = MemoryLayout.size(ofValue: address.sun_path)
        withUnsafeMutableBytes(of: &address.sun_path) { buffer in
            _ = path.withCString { strncpy(buffer.baseAddress!.assumingMemoryBound(to: CChar.self), $0, capacity - 1) }
        }
        if fd >= 0 { McpSocketServer.noSigPipe(fd) }
        let connected = fd >= 0 && withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        } == 0
        if connected { relay(fd) } else { answerWithoutApp() }
    }

    private static func relay(_ fd: Int32) -> Never {
        Thread.detachNewThread {
            var chunk = [UInt8](repeating: 0, count: 16 * 1024)
            while true {
                let n = read(fd, &chunk, chunk.count)
                if n <= 0 { exit(0) }
                FileHandle.standardOutput.write(Data(chunk[0..<n]))
            }
        }
        var chunk = [UInt8](repeating: 0, count: 16 * 1024)
        while true {
            let n = read(STDIN_FILENO, &chunk, chunk.count)
            if n <= 0 { shutdown(fd, SHUT_RDWR); exit(0) }
            var offset = 0
            while offset < n {
                let written = write(fd, &chunk[offset], n - offset)
                if written <= 0 { exit(1) }
                offset += written
            }
        }
    }

    private struct Refuse: McpApproving { func decide(_ request: McpApprovalRequest) async -> McpApprovalDecision { .deny } }

    private static func answerWithoutApp() -> Never {
        let broker = McpBroker(source: { nil }, approver: Refuse())
        let session = McpSession(broker: broker)
        let out = NSLock()
        while let line = readLine(strippingNewline: true) {
            session.receive(Data(line.utf8)) { data in
                out.lock(); defer { out.unlock() }
                FileHandle.standardOutput.write(data + Data([0x0A]))
            }
        }
        // Let in-flight answers finish before the process ends.
        Thread.sleep(forTimeInterval: 0.2)
        exit(0)
    }
}
