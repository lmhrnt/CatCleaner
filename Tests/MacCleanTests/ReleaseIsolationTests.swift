import Foundation
import XCTest

@testable import MacCleanKit

/// Downstream-release guardrails for CatCleaner.
///
/// The fork must not silently regain the upstream Mac Sai cask, release feed,
/// signing profile, or publication authority before CatCleaner owns those
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

    func testReleaseWorkflowIsManualTagBoundAndFailClosed() throws {
        let workflow = repoRoot.appending(path: ".github/workflows/release.yml")
        let source = try String(contentsOf: workflow, encoding: .utf8)

        XCTAssertTrue(source.contains("name: CatCleaner Release"))
        XCTAssertTrue(source.contains("workflow_dispatch:"))
        XCTAssertTrue(source.contains("default: false"))
        XCTAssertTrue(source.contains("if: ${{ inputs.publish == true }}"))
        XCTAssertTrue(source.contains("[[ \"$GITHUB_REF\" == refs/tags/v* ]]"))
        XCTAssertTrue(source.contains("--verify-tag"))
        XCTAssertTrue(source.contains("CATCLEANER_CERTIFICATE_P12_BASE64"))
        XCTAssertTrue(source.contains("CATCLEANER_TEAM_ID"))
        XCTAssertTrue(source.contains("runs-on: macos-15"))
        XCTAssertTrue(source.contains("./scripts/xcode-qualification.sh --full"))
        XCTAssertTrue(source.contains("H3XLS95QV4"))
        XCTAssertFalse(source.contains("homebrew-macsai"))
        XCTAssertFalse(source.contains("MacSai-"))
    }

    func testSigningWorkflowIsVerificationOnlyAndRejectsUpstreamIdentity() throws {
        let workflow = repoRoot.appending(path: ".github/workflows/verify-signing.yml")
        let source = try String(contentsOf: workflow, encoding: .utf8)

        XCTAssertTrue(source.contains("name: CatCleaner Signing Verification"))
        XCTAssertTrue(source.contains("workflow_dispatch:"))
        XCTAssertTrue(source.contains("contents: read"))
        XCTAssertTrue(source.contains("CATCLEANER_CERTIFICATE_P12_BASE64"))
        XCTAssertTrue(source.contains("CATCLEANER_TEAM_ID"))
        XCTAssertTrue(source.contains("runs-on: macos-15"))
        XCTAssertTrue(source.contains("./scripts/xcode-qualification.sh --full"))
        XCTAssertTrue(source.contains("H3XLS95QV4"))
        XCTAssertTrue(source.contains("./scripts/build-dmg.sh --notarize"))
        XCTAssertTrue(source.contains("codesign --verify --deep --strict"))
        XCTAssertTrue(source.contains("xcrun stapler validate"))
        XCTAssertFalse(source.contains("gh release create"))
        XCTAssertFalse(source.contains("contents: write"))
        XCTAssertFalse(source.contains("notarytool store-credentials \"MacSai\""))
    }
}
