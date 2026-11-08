import Foundation
import Testing
@testable import PastportMac

@Suite("Batmobile reference boundary")
struct BatmobileReferencesTests {
    @Test("accepts only bounded repository identities and deduplicates them")
    func parseOnlySanitizedReferences() {
        let output = """
        apple/swift
        Apple/Swift
        someone/project.name
        https://github.com/owner/repo?token=secret
        person@example.com
        owner/repo/extra
        owner/..
        -owner/repo
        """
        #expect(BatmobileReferences.parse(output) == ["apple/swift", "someone/project.name"])
    }

    @Test("passes the selected database and accepts only sanitized helper output")
    func runsSelectedHelper() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let helper = directory.appendingPathComponent("repo-history")
        let database = directory.appendingPathComponent("clipboard.alfdb")
        let script = """
        #!/bin/sh
        test "$1" = alfred && test "$2" = --database && test "$4" = --limit && test "$5" = 5000 || exit 2
        printf 'apple/swift\\nhttps://example.com/private?token=secret\\n'
        """
        try script.write(to: helper, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: helper.path)
        #expect(try await BatmobileReferences.read(helper: helper, database: database) == ["apple/swift"])
    }

    @Test("cancelling a scan stops the selected helper")
    func cancellationStopsHelper() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let helper = directory.appendingPathComponent("repo-history")
        try "#!/bin/sh\nexec /bin/sleep 30\n".write(to: helper, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: helper.path)
        let task = Task { try await BatmobileReferences.read(helper: helper, database: directory.appendingPathComponent("clipboard.alfdb")) }
        try await Task.sleep(for: .milliseconds(100))
        task.cancel()
        do {
            _ = try await task.value
            Issue.record("A cancelled scan must not return results")
        } catch {}
    }
}
