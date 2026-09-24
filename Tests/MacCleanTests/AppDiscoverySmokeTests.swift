import XCTest
import Foundation
@testable import MacClean
import MacCleanKit
import MacCleanTestSupport

final class AppDiscoverySmokeTests: XCTestCase {

    func testDiscoversAtLeastOneApp() async {
        // Every Mac has Safari etc. in /Applications
        let apps = await AppDiscovery().discoverApps()
        XCTAssertGreaterThan(apps.count, 0,
                             "AppDiscovery should find at least one app in /Applications")
    }

    func testAppsAreSortedAlphabetically() async {
        let apps = await AppDiscovery().discoverApps()
        guard apps.count >= 2 else { return }
        for i in 1..<apps.count {
            XCTAssertNotEqual(
                apps[i-1].name.localizedCaseInsensitiveCompare(apps[i].name),
                .orderedDescending,
                "Apps should use the same locale-aware case-insensitive ordering as AppDiscovery"
            )
        }
    }
}
