import XCTest
@testable import MacCleanKit

final class TimeoutTests: XCTestCase {

    func testReturnsValueWhenOperationFinishesInTime() async throws {
        let value = try await withTimeout(.seconds(1)) { 42 }
        XCTAssertEqual(value, 42)
    }

    func testThrowsTimeoutErrorWhenOperationTooSlow() async {
        do {
            _ = try await withTimeout(.milliseconds(50)) {
                try await Task.sleep(for: .seconds(10))
                return 0
            }
            XCTFail("expected withTimeout to throw before the slow operation finished")
        } catch is TimeoutError {
            // expected
        } catch {
            XCTFail("expected TimeoutError, got \(error)")
        }
    }

    func testPropagatesOperationError() async {
        struct Boom: Error {}
        do {
            _ = try await withTimeout(.seconds(1)) { () async throws -> Int in
                throw Boom()
            }
            XCTFail("expected the operation's own error to propagate")
        } catch is Boom {
            // expected: a fast failure surfaces, not a timeout
        } catch {
            XCTFail("expected Boom, got \(error)")
        }
    }

    func testParentCancellationReturnsPromptlyWhenOperationIgnoresCancellation() async {
        let task = Task {
            try await withTimeout(.seconds(10)) {
                await withCheckedContinuation { continuation in
                    DispatchQueue.global().asyncAfter(deadline: .now() + 0.5) {
                        continuation.resume(returning: 42)
                    }
                }
            }
        }

        try? await Task.sleep(for: .milliseconds(30))
        let started = ContinuousClock.now
        task.cancel()

        do {
            _ = try await task.value
            XCTFail("expected CancellationError")
        } catch is CancellationError {
            let elapsed = ContinuousClock.now - started
            XCTAssertLessThan(elapsed, .milliseconds(200))
        } catch {
            XCTFail("expected CancellationError, got \(error)")
        }
    }

    func testTimeoutReturnsPromptlyWhenOperationIgnoresCancellation() async {
        let started = ContinuousClock.now

        do {
            _ = try await withTimeout(.milliseconds(50)) {
                await withCheckedContinuation { continuation in
                    DispatchQueue.global().asyncAfter(deadline: .now() + 0.5) {
                        continuation.resume(returning: 42)
                    }
                }
            }
            XCTFail("expected TimeoutError")
        } catch is TimeoutError {
            let elapsed = ContinuousClock.now - started
            XCTAssertLessThan(
                elapsed,
                .milliseconds(200),
                "timeout must stop waiting even when the operation ignores cancellation"
            )
        } catch {
            XCTFail("expected TimeoutError, got \(error)")
        }
    }
}
