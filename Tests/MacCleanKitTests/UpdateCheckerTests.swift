import XCTest
@testable import MacCleanKit

final class UpdateCheckerTests: XCTestCase {
    // MARK: - isNewer (numeric semver compare)

    func testNewerPatchMinorMajor() {
        XCTAssertTrue(UpdateChecker.isNewer("1.9.1", than: "1.9.0"))
        XCTAssertTrue(UpdateChecker.isNewer("1.10.0", than: "1.9.0"))   // 10 > 9 numerically
        XCTAssertTrue(UpdateChecker.isNewer("2.0.0", than: "1.99.99"))
    }

    func testEqualAndOlderAreNotNewer() {
        XCTAssertFalse(UpdateChecker.isNewer("1.9.0", than: "1.9.0"))
        XCTAssertFalse(UpdateChecker.isNewer("1.9.0", than: "1.10.0"))
    }

    func testShortAndMalformedComponents() {
        XCTAssertTrue(UpdateChecker.isNewer("1.10", than: "1.9.0"))   // pads as 1.10.0
        XCTAssertFalse(UpdateChecker.isNewer("abc", than: "1.9.0"))   // non-numeric reads as 0
    }

    func testAppcastComparisonPrefersMarketingVersionOverBuildNumber() throws {
        let candidate = try XCTUnwrap(UpdateChecker.preferredAppcastVersion(
            shortVersion: "2.1.0",
            buildVersion: "4012"
        ))
        XCTAssertEqual(candidate, "2.1.0")
        XCTAssertFalse(UpdateChecker.isNewer(candidate, than: "2.1.0"))
    }

    // MARK: - parseLatestRelease

    func testParseValidPayload() throws {
        let json = """
        {"tag_name": "v1.10.0", "html_url": "https://example.com/catcleaner/releases/v1.10.0", "name": "1.10.0"}
        """
        let parsed = try XCTUnwrap(UpdateChecker.parseLatestRelease(Data(json.utf8)))
        XCTAssertEqual(parsed.version, "1.10.0")
        XCTAssertEqual(parsed.url.absoluteString, "https://example.com/catcleaner/releases/v1.10.0")
    }

    func testParseRejectsGarbage() {
        XCTAssertNil(UpdateChecker.parseLatestRelease(Data("not json".utf8)))
        XCTAssertNil(UpdateChecker.parseLatestRelease(Data("{}".utf8)))
        // Tag that is only the "v" prefix yields an empty version: reject.
        XCTAssertNil(UpdateChecker.parseLatestRelease(Data(#"{"tag_name": "v", "html_url": "https://example.com"}"#.utf8)))
    }

    // MARK: - Homebrew detection

    func testHomebrewDetection() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appending(path: "caskroom-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }

        XCTAssertTrue(UpdateChecker.isHomebrewInstall(caskroomPaths: [tmp.path]))
        XCTAssertFalse(UpdateChecker.isHomebrewInstall(caskroomPaths: ["/nonexistent/caskroom/catcleaner"]))
    }

    // MARK: - Align the updater with what Homebrew can actually deliver

    func testParseCaskVersion() {
        let json = #"{"token":"catcleaner","version":"1.16.0","homepage":"https://example.com/catcleaner"}"#
        XCTAssertEqual(UpdateChecker.parseCaskVersion(Data(json.utf8)), "1.16.0")
    }

    func testParseCaskVersionRejectsGarbageAndLatest() {
        XCTAssertNil(UpdateChecker.parseCaskVersion(Data("not json".utf8)))
        XCTAssertNil(UpdateChecker.parseCaskVersion(Data("{}".utf8)))
        // ":latest" casks have no comparable version.
        XCTAssertNil(UpdateChecker.parseCaskVersion(Data(#"{"version":":latest"}"#.utf8)))
    }

    func testDownstreamUpdateSourcesAreFailClosedUntilConfigured() {
        XCTAssertFalse(MCConstants.updateChecksEnabled)
        XCTAssertNil(UpdateChecker.updateSourceURL(isHomebrew: true))
        XCTAssertNil(UpdateChecker.updateSourceURL(isHomebrew: false))
        XCTAssertNil(MCConstants.homebrewCaskAPI)
        XCTAssertNil(MCConstants.latestReleaseAPI)
    }
}
