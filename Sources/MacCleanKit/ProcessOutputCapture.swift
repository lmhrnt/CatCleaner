import Foundation

public struct ProcessOutputCaptureResult: Sendable, Equatable {
    public let exitCode: Int32
    public let stdout: String
    public let stderr: String

    public init(exitCode: Int32, stdout: String, stderr: String) {
        self.exitCode = exitCode
        self.stdout = stdout
        self.stderr = stderr
    }
}

/// Synchronously runs a fixed executable while continuously draining stdout
/// and stderr on separate queues.
///
/// Calling `waitUntilExit()` before reading pipes can deadlock when either
/// stream exceeds the kernel pipe buffer. This helper keeps both streams
/// draining until EOF, then returns their complete UTF-8 output.
public enum ProcessOutputCapture {
    public static func run(
        executable: URL,
        arguments: [String] = [],
        environment: [String: String]? = nil
    ) throws -> ProcessOutputCaptureResult {
        let process = Process()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()

        process.executableURL = executable
        process.arguments = arguments
        if let environment {
            process.environment = environment
        }
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        try process.run()

        // The child owns duplicated write descriptors after spawn. Close the
        // parent's write handles so the readers observe EOF when the child
        // exits instead of waiting on descriptors retained by this process.
        try? stdoutPipe.fileHandleForWriting.close()
        try? stderrPipe.fileHandleForWriting.close()

        let stdoutBox = LockedDataBox()
        let stderrBox = LockedDataBox()
        let group = DispatchGroup()

        group.enter()
        DispatchQueue.global(qos: .utility).async {
            stdoutBox.store(stdoutPipe.fileHandleForReading.readDataToEndOfFile())
            group.leave()
        }

        group.enter()
        DispatchQueue.global(qos: .utility).async {
            stderrBox.store(stderrPipe.fileHandleForReading.readDataToEndOfFile())
            group.leave()
        }

        process.waitUntilExit()
        group.wait()

        return ProcessOutputCaptureResult(
            exitCode: process.terminationStatus,
            stdout: String(data: stdoutBox.load(), encoding: .utf8) ?? "",
            stderr: String(data: stderrBox.load(), encoding: .utf8) ?? ""
        )
    }

    private final class LockedDataBox: @unchecked Sendable {
        private let lock = NSLock()
        private var data = Data()

        func store(_ newValue: Data) {
            lock.lock()
            data = newValue
            lock.unlock()
        }

        func load() -> Data {
            lock.lock()
            defer { lock.unlock() }
            return data
        }
    }
}
