import Foundation
import XCTest

@testable import MacCleanKit

final class ScanSelectionPolicyTests: XCTestCase {
    func testOnlyAutoSelectResultsContributeURLs() {
        let safe = item("/tmp/safe-cache", size: 100)
        let malware = item("/tmp/threat", size: 200)
        let privacy = item("/tmp/history", size: 300)
        let duplicate = item("/tmp/copy", size: 400)

        let selected = ScanSelectionPolicy.defaultSelection(from: [
            ScanResult(category: .userCaches, items: [safe]),
            ScanResult(category: .malware, items: [malware]),
            ScanResult(category: .browserPrivacy, items: [privacy]),
            ScanResult(category: .duplicates, items: [duplicate]),
        ])

        XCTAssertEqual(selected, [safe.url])
    }

    func testModuleOverloadUsesSamePolicy() {
        let safe = item("/tmp/log")
        let trash = item("/tmp/trash")

        let modules = [
            ModuleScanResult(
                moduleID: "one",
                moduleName: "One",
                categories: [
                    ScanResult(category: .userLogs, items: [safe]),
                    ScanResult(category: .trashBins, items: [trash]),
                ],
                scanDuration: 0
            )
        ]

        XCTAssertEqual(
            ScanSelectionPolicy.defaultSelection(from: modules),
            [safe.url]
        )
    }

    func testDuplicateURLsAreCollapsed() {
        let shared = item("/tmp/shared")

        let selected = ScanSelectionPolicy.defaultSelection(from: [
            ScanResult(category: .userCaches, items: [shared]),
            ScanResult(category: .userLogs, items: [shared]),
        ])

        XCTAssertEqual(selected, [shared.url])
    }

    func testExplicitReviewOnlyOverrideStaysUnselected() {
        let cache = item("/tmp/cache")

        let selected = ScanSelectionPolicy.defaultSelection(from: [
            ScanResult(
                category: .userCaches,
                items: [cache],
                autoSelect: false
            )
        ])

        XCTAssertTrue(selected.isEmpty)
    }

    private func item(_ path: String, size: UInt64 = 1) -> FileItem {
        FileItem(
            url: URL(fileURLWithPath: path),
            name: URL(fileURLWithPath: path).lastPathComponent,
            size: size,
            allocatedSize: size,
            isDirectory: false
        )
    }
}
