import Foundation
import XCTest

@testable import MacCleanKit

final class DeveloperCleanupTests: XCTestCase {
    private var tempHome: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempHome = FileManager.default.temporaryDirectory
            .appendingPathComponent("CatCleaner-DeveloperCleanup-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempHome, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let tempHome {
            try? FileManager.default.removeItem(at: tempHome)
        }
        try super.tearDownWithError()
    }

    func testRebuildableNpxCacheIsCleanableWhenInactive() async throws {
        try createFile(relativePath: ".npm/_npx/example/package.json", bytes: 4096)

        let results = await DeveloperCleanupScanner(
            homeURL: tempHome,
            processSnapshot: ""
        ).scan()

        let candidate = try XCTUnwrap(results.first { $0.id == "npx-ephemeral-cache" })
        XCTAssertEqual(candidate.kind, .rebuildableCache)
        XCTAssertEqual(candidate.disposition, .safeWhenInactive)
        XCTAssertFalse(candidate.ownerActive)
        XCTAssertTrue(candidate.canBecomeCleanable)
        XCTAssertGreaterThan(candidate.allocatedSize, 0)
    }

    func testRebuildableCacheIsBlockedWhileOwnerIsActive() async throws {
        try createFile(relativePath: ".npm/_npx/example/package.json", bytes: 4096)

        let results = await DeveloperCleanupScanner(
            homeURL: tempHome,
            processSnapshot: "/opt/homebrew/bin/npx some-package"
        ).scan()

        let candidate = try XCTUnwrap(results.first { $0.id == "npx-ephemeral-cache" })
        XCTAssertTrue(candidate.ownerActive)
        XCTAssertFalse(candidate.canBecomeCleanable)
    }

    func testRecoveryDataRequiresRetentionReview() async throws {
        try createFile(relativePath: ".catdesk/recovery_bin/op-1/manifest.json", bytes: 2048)

        let results = await DeveloperCleanupScanner(
            homeURL: tempHome,
            processSnapshot: ""
        ).scan()

        let candidate = try XCTUnwrap(results.first { $0.id == "catdesk-recovery" })
        XCTAssertEqual(candidate.kind, .boundedRetention)
        XCTAssertEqual(candidate.disposition, .retentionReview)
        XCTAssertFalse(candidate.canBecomeCleanable)
    }

    func testStatefulSessionsAreReportOnly() async throws {
        try createFile(relativePath: ".codex/sessions/session.jsonl", bytes: 2048)

        let results = await DeveloperCleanupScanner(
            homeURL: tempHome,
            processSnapshot: ""
        ).scan()

        let candidate = try XCTUnwrap(results.first { $0.id == "codex-sessions" })
        XCTAssertEqual(candidate.kind, .statefulRuntime)
        XCTAssertEqual(candidate.disposition, .reportOnly)
        XCTAssertFalse(candidate.canBecomeCleanable)
    }

    func testResultsAreSortedByAllocatedSizeDescending() async throws {
        try createFile(relativePath: ".npm/_npx/small.bin", bytes: 4096)
        try createFile(relativePath: ".codex/sessions/large.bin", bytes: 128 * 1024)

        let results = await DeveloperCleanupScanner(
            homeURL: tempHome,
            processSnapshot: ""
        ).scan()

        XCTAssertGreaterThanOrEqual(results.count, 2)
        XCTAssertGreaterThanOrEqual(results[0].allocatedSize, results[1].allocatedSize)
    }

    private func createFile(relativePath: String, bytes: Int) throws {
        let url = tempHome.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data(repeating: 0x5A, count: bytes).write(to: url)
    }
}
