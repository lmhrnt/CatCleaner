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

public enum ProcessOutputCaptureError: Error, Equatable, LocalizedError, Sendable {
    case timedOut

    public var errorDescription: String? {
        switch self {
        case .timedOut:
            "Process exceeded its execution timeout."
        }
    }
}

/// Synchronously runs a fixed executable while continuously draining stdout
/// and stderr on separate queues.
///
/// Calling `waitUntilExit()` before reading pipes can deadlock when either
/// stream exceeds the kernel pipe buffer. This helper keeps both streams
/// draining while the child runs. Callers may also provide a timeout; when it
/// expires the child is terminated, escalated to SIGKILL if needed, and the
/// pipe readers are closed so this function does not wait forever for EOF.
public enum ProcessOutputCapture {
    private static let terminationGraceSeconds: TimeInterval = 0.05

    public static func run(
        executable: URL,
        arguments: [String] = [],
        environment: [String: String]? = nil,
        timeout: TimeInterval? = nil
    ) throws -> ProcessOutputCaptureResult {
        let process = Process()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        let termination = DispatchSemaphore(value: 0)

        process.executableURL = executable
        process.arguments = arguments
        if let environment {
            process.environment = environment
        }
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        process.terminationHandler = { _ in termination.signal() }

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

        let timedOut: Bool
        if let timeout {
            let deadline = DispatchTime.now() + timeout
            timedOut = termination.wait(timeout: deadline) == .timedOut
        } else {
            termination.wait()
            timedOut = false
        }

        if timedOut {
            terminate(process)
            // Closing the read handles guarantees the background drainers do
            // not remain blocked if descendants inherited the pipe writers.
            try? stdoutPipe.fileHandleForReading.close()
            try? stderrPipe.fileHandleForReading.close()
            _ = group.wait(timeout: .now() + terminationGraceSeconds)
            throw ProcessOutputCaptureError.timedOut
        }

        group.wait()

        return ProcessOutputCaptureResult(
            exitCode: process.terminationStatus,
            stdout: String(data: stdoutBox.load(), encoding: .utf8) ?? "",
            stderr: String(data: stderrBox.load(), encoding: .utf8) ?? ""
        )
    }

    private static func terminate(_ process: Process) {
        guard process.isRunning else { return }
        process.terminate()

        let deadline = Date().addingTimeInterval(terminationGraceSeconds)
        while process.isRunning, Date() < deadline {
            Thread.sleep(forTimeInterval: 0.01)
        }

        if process.isRunning {
            kill(process.processIdentifier, SIGKILL)
        }
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
