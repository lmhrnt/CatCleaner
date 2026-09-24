import XCTest
@testable import MacCleanKit

final class CleaningAutomationTests: XCTestCase {
    func testBrowserBundleMapping() {
        XCTAssertEqual(BrowserCleanupTarget.target(for: "com.apple.Safari"), .safari)
        XCTAssertEqual(BrowserCleanupTarget.target(for: "com.google.Chrome"), .chrome)
        XCTAssertEqual(BrowserCleanupTarget.target(for: "org.mozilla.firefox"), .firefox)
        XCTAssertNil(BrowserCleanupTarget.target(for: "com.example.not-a-browser"))
    }

    func testSafeCacheRootsNeverIncludeProfileOrCredentialStores() {
        for browser in BrowserCleanupTarget.allCases {
            for root in browser.safeCacheRoots {
                let path = root.path(percentEncoded: false).lowercased()
                XCTAssertTrue(path.contains("cache"))
                XCTAssertFalse(path.contains("cookie"))
                XCTAssertFalse(path.contains("password"))
                XCTAssertFalse(path.contains("keychain"))
                XCTAssertFalse(path.contains("bookmark"))
            }
        }
    }

    func testBrowserTerminationRequiresOptInAndFullExit() {
        XCTAssertFalse(
            CleaningAutomationPolicy.shouldHandleBrowserTermination(
                browser: .chrome,
                mode: .off,
                browserEnabled: true,
                stillRunning: false
            )
        )
        XCTAssertFalse(
            CleaningAutomationPolicy.shouldHandleBrowserTermination(
                browser: .chrome,
                mode: .moveSafeCachesToTrash,
                browserEnabled: true,
                stillRunning: true
            )
        )
        XCTAssertTrue(
            CleaningAutomationPolicy.shouldHandleBrowserTermination(
                browser: .chrome,
                mode: .notify,
                browserEnabled: true,
                stillRunning: false
            )
        )
    }

    func testOnlyExplicitTrashModePerformsAutomaticCleanup() {
        XCTAssertFalse(CleaningAutomationPolicy.shouldAutoCleanBrowser(mode: .off))
        XCTAssertFalse(CleaningAutomationPolicy.shouldAutoCleanBrowser(mode: .notify))
        XCTAssertTrue(
            CleaningAutomationPolicy.shouldAutoCleanBrowser(mode: .moveSafeCachesToTrash)
        )
    }

    func testSmartCleaningThresholdIsClamped() {
        XCTAssertFalse(
            CleaningAutomationPolicy.shouldRaiseSmartCleaningAlert(
                reclaimableBytes: 99_999_999,
                thresholdMB: 1
            )
        )
        XCTAssertTrue(
            CleaningAutomationPolicy.shouldRaiseSmartCleaningAlert(
                reclaimableBytes: 100_000_000,
                thresholdMB: 1
            )
        )
    }

    func testTrashAgePolicyRequiresKnownOldModificationDate() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        XCTAssertFalse(
            CleaningAutomationPolicy.shouldEmptyTrashItem(
                modificationDate: nil,
                now: now,
                minimumAgeDays: 30
            )
        )
        XCTAssertTrue(
            CleaningAutomationPolicy.shouldEmptyTrashItem(
                modificationDate: now.addingTimeInterval(-31 * 86_400),
                now: now,
                minimumAgeDays: 30
            )
        )
        XCTAssertFalse(
            CleaningAutomationPolicy.shouldEmptyTrashItem(
                modificationDate: now.addingTimeInterval(-29 * 86_400),
                now: now,
                minimumAgeDays: 30
            )
        )
    }
}
