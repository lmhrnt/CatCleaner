import Foundation

/// Thrown by ``withTimeout(_:_:)`` when the operation outlives its budget.
public struct TimeoutError: Error, Equatable {
    public init() {}
}

/// Run `operation`, returning its result, or throw ``TimeoutError`` if it does
/// not finish within `duration`.
///
/// IMPORTANT: Swift task cancellation is cooperative. If `operation` is blocked
/// inside a non-cancellable C/syscall, timeout stops *waiting* for that work but
/// cannot kill it. The timed-out operation may continue in its unstructured task
/// until the underlying call returns. Callers must therefore avoid repeatedly
/// stacking work that can remain blocked forever.
public func withTimeout<T: Sendable>(
    _ duration: Duration,
    _ operation: @escaping @Sendable () async throws -> T
) async throws -> T {
    let race = TimeoutRace<T>()

    return try await withTaskCancellationHandler {
        try await withCheckedThrowingContinuation { continuation in
            race.start(
                continuation: continuation,
                duration: duration,
                operation: operation
            )
        }
    } onCancel: {
        race.finish(.failure(CancellationError()))
    }
}

private final class TimeoutRace<T: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<T, any Error>?
    private var pendingCompletion: Result<T, any Error>?
    private var operationTask: Task<Void, Never>?
    private var timeoutTask: Task<Void, Never>?
    private var resolved = false

    func start(
        continuation: CheckedContinuation<T, any Error>,
        duration: Duration,
        operation: @escaping @Sendable () async throws -> T
    ) {
        lock.lock()
        if resolved {
            let completion = pendingCompletion
            pendingCompletion = nil
            lock.unlock()

            if let completion {
                continuation.resume(with: completion)
            } else {
                continuation.resume(throwing: CancellationError())
            }
            return
        }

        self.continuation = continuation
        lock.unlock()

        let operationTask = Task.detached(priority: .userInitiated) {
            do {
                let value = try await operation()
                self.finish(.success(value))
            } catch {
                self.finish(.failure(error))
            }
        }

        let timeoutTask = Task.detached(priority: .userInitiated) {
            do {
                try await Task.sleep(for: duration)
                self.finish(.failure(TimeoutError()))
            } catch {
                // The opposing branch won and cancelled this sleeper.
            }
        }

        installTasks(operation: operationTask, timeout: timeoutTask)
    }

    func finish(_ completion: Result<T, any Error>) {
        lock.lock()
        guard !resolved else {
            lock.unlock()
            return
        }

        resolved = true
        let continuation = self.continuation
        self.continuation = nil

        if continuation == nil {
            pendingCompletion = completion
        }

        let operationTask = self.operationTask
        let timeoutTask = self.timeoutTask
        self.operationTask = nil
        self.timeoutTask = nil
        lock.unlock()

        operationTask?.cancel()
        timeoutTask?.cancel()
        continuation?.resume(with: completion)
    }

    private func installTasks(
        operation: Task<Void, Never>,
        timeout: Task<Void, Never>
    ) {
        lock.lock()
        if resolved {
            lock.unlock()
            operation.cancel()
            timeout.cancel()
            return
        }

        operationTask = operation
        timeoutTask = timeout
        lock.unlock()
    }
}
