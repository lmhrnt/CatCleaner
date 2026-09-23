import Foundation
import XCTest

@testable import MacCleanKit

/// Downstream-release guardrails for CatCleaner.
///
/// The fork must not silently regain the upstream Mac Sai cask, release feed,
/// signing profile, or publication workflow before CatCleaner owns those
/// identities itself.
final class ReleaseIsolationTests: XCTestCase {
    private var repoRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    func testUpstreamHomebrewCaskIsNotPublishedByFork() {
        let upstreamCask = repoRoot.appending(path: "Casks/mac-sai.rb")
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: upstreamCask.path),
            "CatCleaner must not publish the upstream Mac Sai cask"
        )
    }

    func testUpdateFeedsRemainFailClosedUntilCatCleanerOwnsThem() {
        XCTAssertFalse(MCConstants.updateChecksEnabled)
        XCTAssertNil(MCConstants.latestReleaseAPI)
        XCTAssertNil(MCConstants.homebrewCaskAPI)
        XCTAssertNil(MCConstants.releasesURL)
        XCTAssertNil(MCConstants.issuesURL)
    }

    func testReleaseWorkflowIsExplicitlyDisabled() throws {
        let workflow = repoRoot.appending(path: ".github/workflows/release.yml")
        let source = try String(contentsOf: workflow, encoding: .utf8)

        XCTAssertTrue(source.contains("CatCleaner Release (disabled)"))
        XCTAssertTrue(source.contains("Release infrastructure not configured"))
        XCTAssertFalse(source.contains("homebrew-macsai"))
        XCTAssertFalse(source.contains("MacSai-"))
    }

    func testSigningWorkflowDoesNotReuseUpstreamIdentity() throws {
        let workflow = repoRoot.appending(path: ".github/workflows/verify-signing.yml")
        let source = try String(contentsOf: workflow, encoding: .utf8)

        XCTAssertTrue(source.contains("CatCleaner Signing Verification (disabled)"))
        XCTAssertTrue(source.contains("Do not reuse the upstream Mac Sai notary profile or Developer Team ID."))
        XCTAssertFalse(source.contains("notarytool store-credentials \"MacSai\""))
    }
}
