import Foundation
import XCTest

@testable import MacCleanKit

final class ProcessOutputCaptureTests: XCTestCase {
    func testDrainsLargeStdoutAndStderrWithoutPipeDeadlock() throws {
        let script = #"""
        for ((i=1; i<=20000; i++)); do
          printf 'OUT%05d\n' "$i"
          printf 'ERR%05d\n' "$i" >&2
        done
        """#

        let result = try ProcessOutputCapture.run(
            executable: URL(fileURLWithPath: "/bin/bash"),
            arguments: ["-lc", script]
        )

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertGreaterThan(result.stdout.utf8.count, 64 * 1024)
        XCTAssertGreaterThan(result.stderr.utf8.count, 64 * 1024)
        XCTAssertTrue(result.stdout.contains("OUT20000"))
        XCTAssertTrue(result.stderr.contains("ERR20000"))
    }

    func testPreservesSeparatedStreamsOnFailure() throws {
        let result = try ProcessOutputCapture.run(
            executable: URL(fileURLWithPath: "/bin/bash"),
            arguments: [
                "-lc",
                "printf 'normal-output'; printf 'diagnostic-output' >&2; exit 23",
            ]
        )

        XCTAssertEqual(result.exitCode, 23)
        XCTAssertEqual(result.stdout, "normal-output")
        XCTAssertEqual(result.stderr, "diagnostic-output")
    }

    func testTimeoutStopsWaitingForHungProcess() {
        let started = ContinuousClock.now

        XCTAssertThrowsError(
            try ProcessOutputCapture.run(
                executable: URL(fileURLWithPath: "/bin/sleep"),
                arguments: ["5"],
                timeout: 0.05
            )
        ) { error in
            XCTAssertEqual(error as? ProcessOutputCaptureError, .timedOut)
        }

        let elapsed = ContinuousClock.now - started
        XCTAssertLessThan(elapsed, .milliseconds(500))
    }
}
