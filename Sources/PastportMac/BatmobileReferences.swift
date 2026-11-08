import Foundation

/// A bounded, user-invoked bridge to Batmobile's `repo-history` command.
/// Only repository identities are returned; clipboard rows and diagnostics are discarded.
public enum BatmobileReferences {
    public enum Failure: Error { case invalidHelper, scanFailed, outputTooLarge }

    public static func parse(_ output: String) -> [String] {
        var seen = Set<String>()
        return output.split(whereSeparator: \.isNewline).compactMap { line in
            let value = String(line)
            let parts = value.split(separator: "/", omittingEmptySubsequences: false)
            guard value.range(of: #"^[A-Za-z0-9][A-Za-z0-9-]{0,38}/[A-Za-z0-9_.-]{1,100}$"#, options: .regularExpression) != nil,
                  parts.count == 2, parts[1] != ".", parts[1] != "..",
                  seen.insert(value.lowercased()).inserted else { return nil }
            return value
        }
    }

    /// The caller must obtain explicit user consent for both paths before starting this process.
    public static func read(helper: URL, database: URL) async throws -> [String] {
        let child = ChildProcess()
        return try await withTaskCancellationHandler {
            try await Task.detached(priority: .userInitiated) {
                let helperScoped = helper.startAccessingSecurityScopedResource()
                let databaseScoped = database.startAccessingSecurityScopedResource()
                defer {
                    if helperScoped { helper.stopAccessingSecurityScopedResource() }
                    if databaseScoped { database.stopAccessingSecurityScopedResource() }
                }
                guard helper.lastPathComponent == "repo-history",
                      FileManager.default.isExecutableFile(atPath: helper.path) else { throw Failure.invalidHelper }
                let process = Process()
                process.executableURL = helper
                process.arguments = ["alfred", "--database", database.path, "--limit", "5000"]
                let output = Pipe()
                process.standardOutput = output
                process.standardError = FileHandle.nullDevice
                try child.start(process)
                defer { child.finish() }
                var bytes = Data()
                while let chunk = try output.fileHandleForReading.read(upToCount: 8192), !chunk.isEmpty {
                    bytes.append(chunk)
                    if bytes.count > 262_144 {
                        child.cancel()
                        throw Failure.outputTooLarge
                    }
                }
                process.waitUntilExit()
                guard !child.isCancelled, process.terminationStatus == 0,
                      let text = String(data: bytes, encoding: .utf8) else { throw Failure.scanFailed }
                return parse(text)
            }.value
        } onCancel: {
            child.cancel()
        }
    }
}

private final class ChildProcess: @unchecked Sendable {
    private let lock = NSLock()
    private var process: Process?
    private var cancelled = false

    var isCancelled: Bool { lock.lock(); defer { lock.unlock() }; return cancelled }

    func start(_ process: Process) throws {
        lock.lock(); defer { lock.unlock() }
        guard !cancelled else { throw CancellationError() }
        try process.run()
        self.process = process
    }

    func cancel() {
        lock.lock(); defer { lock.unlock() }
        cancelled = true
        if let process, process.isRunning { process.terminate() }
    }

    func finish() { lock.lock(); defer { lock.unlock() }; process = nil }
}
