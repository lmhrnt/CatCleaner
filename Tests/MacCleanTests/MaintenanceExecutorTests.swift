import AppKit
import XCTest
@testable import MacClean
@testable import MacCleanKit

/// Issue #143: each admin task used to spawn a fresh `/usr/bin/osascript`
/// process, so macOS could not cache the password. The executor must send
/// every privileged command through one injected in-process runner.
final class MaintenanceExecutorTests: EnglishAppLanguageTestCase {

    func testAdminTaskGoesThroughPrivilegedRunner() async {
        let runner = RecordingPrivilegedRunner(
            result: .ok("purged")
        )
        let executor = MaintenanceExecutor(
            privilegedRunner: runner,
            commandExists: { _ in true }
        )

        let result = await executor.execute(.freeUpRAM)

        XCTAssertTrue(result.success)
        XCTAssertEqual(result.output, "purged")
        XCTAssertEqual(runner.commandLines, [
            MaintenanceShell.commandLine("/usr/sbin/purge", [])
        ])
    }

    func testSequentialAdminTasksReuseTheSameRunner() async {
        let runner = RecordingPrivilegedRunner(result: .ok(""))
        let executor = MaintenanceExecutor(
            privilegedRunner: runner,
            commandExists: { _ in true }
        )

        _ = await executor.execute(.freeUpRAM)
        _ = await executor.execute(.freeUpPurgeableSpace)
        _ = await executor.execute(.runMaintenanceScripts)

        XCTAssertEqual(runner.commandLines, [
            MaintenanceShell.commandLine("/usr/sbin/purge", []),
            MaintenanceShell.commandLine("/usr/bin/tmutil", ["thinlocalsnapshots", "/", "999999999999", "1"]),
            MaintenanceShell.commandLine("/usr/sbin/periodic", ["daily", "weekly", "monthly"]),
        ])
    }

    func testUnprivilegedTaskDoesNotTouchPrivilegedRunner() async {
        let runner = RecordingPrivilegedRunner(result: .ok("unused"))
        let executor = MaintenanceExecutor(
            privilegedRunner: runner,
            commandExists: { _ in true }
        )

        _ = await executor.execute(.flushDNSCache)

        XCTAssertTrue(
            runner.commandLines.isEmpty,
            "non-admin tasks must not trigger the password prompt"
        )
    }

    func testMissingBinaryDoesNotPromptForAdmin() async {
        let runner = RecordingPrivilegedRunner(result: .ok("should not run"))
        let executor = MaintenanceExecutor(
            privilegedRunner: runner,
            commandExists: { _ in false }
        )

        let result = await executor.execute(.runMaintenanceScripts)

        XCTAssertFalse(result.success)
        XCTAssertTrue(runner.commandLines.isEmpty, "password prompt must not appear for a missing tool")
        XCTAssertEqual(
            result.error,
            "/usr/sbin/periodic isn't available on this version of macOS, so this task can't run."
        )
    }

    func testUserCancelIsMappedToFriendlyMessage() async {
        let runner = RecordingPrivilegedRunner(
            result: .failed("User canceled.", errorNumber: -128)
        )
        let executor = MaintenanceExecutor(
            privilegedRunner: runner,
            commandExists: { _ in true }
        )

        let result = await executor.execute(.freeUpRAM)

        XCTAssertFalse(result.success)
        XCTAssertEqual(result.error, "Cancelled — administrator access was not granted.")
    }

    func testAdminFailureStripsAppleScriptWrapper() async {
        let runner = RecordingPrivilegedRunner(
            result: .failed("1:92: execution error: Operation not permitted (1)")
        )
        let executor = MaintenanceExecutor(
            privilegedRunner: runner,
            commandExists: { _ in true }
        )

        let result = await executor.execute(.freeUpRAM)

        XCTAssertFalse(result.success)
        XCTAssertEqual(result.error, "Operation not permitted")
    }

    func testMailReindexBlocksWhileMailIsRunning() async throws {
        let root = try makeMailFixture()
        defer { try? FileManager.default.removeItem(at: root) }

        let mailData = root.appendingPathComponent("V10/MailData")
        try FileManager.default.createDirectory(
            at: mailData,
            withIntermediateDirectories: true
        )
        let index = mailData.appendingPathComponent("Envelope Index")
        try Data("index".utf8).write(to: index)

        let trash = RecordingTrash()
        let executor = MaintenanceExecutor(
            privilegedRunner: RecordingPrivilegedRunner(result: .ok("")),
            commandExists: { _ in true },
            mailRoot: root,
            mailIsRunning: { true },
            trashItem: { trash.record($0) }
        )

        let result = await executor.execute(.speedUpMail)

        XCTAssertFalse(result.success)
        XCTAssertTrue(trash.urls.isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: index.path))
        XCTAssertEqual(
            result.error,
            "Quit Mail.app completely before rebuilding its index."
        )
    }

    func testMailReindexUsesNewestVersionWithCompleteMainIndex() async throws {
        let root = try makeMailFixture()
        defer { try? FileManager.default.removeItem(at: root) }

        let v9 = root.appendingPathComponent("V9/MailData")
        let v10 = root.appendingPathComponent("V10/MailData")
        let v11 = root.appendingPathComponent("V11/MailData")
        for dir in [v9, v10, v11] {
            try FileManager.default.createDirectory(
                at: dir,
                withIntermediateDirectories: true
            )
        }

        try Data("old".utf8).write(
            to: v9.appendingPathComponent("Envelope Index")
        )
        try Data("current".utf8).write(
            to: v10.appendingPathComponent("Envelope Index")
        )
        try Data("wal".utf8).write(
            to: v10.appendingPathComponent("Envelope Index-wal")
        )
        try Data("shm".utf8).write(
            to: v10.appendingPathComponent("Envelope Index-shm")
        )

        // A higher version directory with only a stray WAL is not a complete
        // current index family and must not shadow V10.
        try Data("stale".utf8).write(
            to: v11.appendingPathComponent("Envelope Index-wal")
        )

        let trash = RecordingTrash()
        let executor = MaintenanceExecutor(
            privilegedRunner: RecordingPrivilegedRunner(result: .ok("")),
            commandExists: { _ in true },
            mailRoot: root,
            mailIsRunning: { false },
            trashItem: { trash.record($0) }
        )

        let result = await executor.execute(.speedUpMail)

        XCTAssertTrue(result.success, result.error ?? "")
        XCTAssertEqual(trash.urls.count, 3)
        XCTAssertEqual(
            Set(trash.urls.map(\.lastPathComponent)),
            Set(["Envelope Index", "Envelope Index-wal", "Envelope Index-shm"])
        )
        XCTAssertTrue(
            trash.urls.allSatisfy {
                $0.path.contains("/V10/MailData/")
            }
        )
        XCTAssertFalse(
            trash.urls.contains {
                $0.path.contains("/V9/") || $0.path.contains("/V11/")
            }
        )
    }

    func testMailCandidateSelectionRequiresRegularMainIndex() throws {
        let root = try makeMailFixture()
        defer { try? FileManager.default.removeItem(at: root) }

        let v10 = root.appendingPathComponent("V10/MailData")
        try FileManager.default.createDirectory(
            at: v10,
            withIntermediateDirectories: true
        )

        let outside = root.appendingPathComponent("outside-index")
        try Data("outside".utf8).write(to: outside)

        let link = v10.appendingPathComponent("Envelope Index")
        try FileManager.default.createSymbolicLink(
            at: link,
            withDestinationURL: outside
        )

        XCTAssertTrue(
            MaintenanceExecutor.mailIndexCandidates(
                mailRoot: root,
                fileManager: .default
            ).isEmpty
        )
    }

    /// `NSAppleScript` is documented as main-thread-only. The production
    /// runner uses a dedicated serial queue so long `periodic` jobs don't
    /// freeze the UI. This proves `do shell script` (no admin) still works
    /// on that kind of queue — same API the runner uses.
    func testDoShellScriptWorksOffMainThread() async {
        let result: (String?, NSDictionary?) = await withCheckedContinuation { continuation in
            DispatchQueue(label: "sai.test.applescript").async {
                var error: NSDictionary?
                let script = NSAppleScript(source: "do shell script \"echo ok\"")
                let descriptor = script?.executeAndReturnError(&error)
                continuation.resume(returning: (descriptor?.stringValue, error))
            }
        }
        XCTAssertNil(result.1, "off-main do shell script failed: \(result.1 ?? [:])")
        XCTAssertEqual(result.0, "ok")
    }

    private func makeMailFixture() throws -> URL {
        let root = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Caches")
            .appendingPathComponent("CatCleaner-MailReindexTests")
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: true
        )
        return root
    }

    func testGeneratedAdminScriptsCompile() {
        let commands = MaintenanceTask.allCases.compactMap { task -> String? in
            guard task.requiresAdmin, let command = task.systemCommand else { return nil }
            return MaintenanceShell.commandLine(command.executable, command.arguments)
        }
        XCTAssertEqual(commands.count, 5, "every admin task with a systemCommand should compile")
        for command in commands {
            let source = MaintenanceShell.appleScriptSource(commandLine: command)
            var error: NSDictionary?
            let script = NSAppleScript(source: source)
            XCTAssertNotNil(script, source)
            XCTAssertTrue(
                script?.compileAndReturnError(&error) == true,
                "compile failed for \(command): \(error ?? [:])"
            )
        }
    }
}

/// Records every privileged command line. `@unchecked Sendable` because the
/// executor is an actor and tests await it sequentially — no concurrent
/// mutation.
final class RecordingTrash: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [URL] = []

    var urls: [URL] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    func record(_ url: URL) {
        lock.lock()
        storage.append(url)
        lock.unlock()
    }
}

final class RecordingPrivilegedRunner: PrivilegedShellRunning, @unchecked Sendable {
    private(set) var commandLines: [String] = []
    var result: PrivilegedShellResult

    init(result: PrivilegedShellResult) {
        self.result = result
    }

    func run(commandLine: String) async -> PrivilegedShellResult {
        commandLines.append(commandLine)
        return result
    }
}
