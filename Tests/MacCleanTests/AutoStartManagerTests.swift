import Foundation
import XCTest

@testable import MacClean
import MacCleanKit

final class AutoStartManagerTests: XCTestCase {
    func testJSONLoginItemParserUsesPathResolverForBundleIdentifier() {
        let json = """
        [
          {"name":"Stats","path":"/Applications/Stats.app","hidden":false},
          {"name":"Microsoft SharePoint","path":null,"hidden":false}
        ]
        """

        let items = AutoStartManager.parseSystemEventsLoginItems(
            json,
            bundleIdentifierForPath: { path in
                path == "/Applications/Stats.app"
                    ? "eu.exelban.Stats"
                    : nil
            }
        )

        XCTAssertEqual(items.count, 2)

        let stats = items[0]
        XCTAssertEqual(stats.name, "Stats")
        XCTAssertEqual(stats.bundleIdentifier, "eu.exelban.Stats")
        XCTAssertEqual(stats.programPath, "/Applications/Stats.app")
        XCTAssertTrue(stats.canToggle)

        let sharePoint = items[1]
        XCTAssertEqual(sharePoint.name, "Microsoft SharePoint")
        XCTAssertNil(sharePoint.bundleIdentifier)
        XCTAssertNil(sharePoint.programPath)
        XCTAssertFalse(sharePoint.canToggle)
    }

    func testParserTreatsMissingValuePathAsUnavailable() {
        let json = """
        [{"name":"Legacy Item","path":"missing value","hidden":false}]
        """

        let items = AutoStartManager.parseSystemEventsLoginItems(
            json,
            bundleIdentifierForPath: { _ in
                XCTFail("bundle resolver must not run for missing path")
                return "unexpected"
            }
        )

        XCTAssertEqual(items.count, 1)
        XCTAssertNil(items[0].programPath)
        XCTAssertNil(items[0].bundleIdentifier)
        XCTAssertFalse(items[0].canToggle)
    }

    func testParserRejectsMalformedJSON() {
        XCTAssertTrue(
            AutoStartManager.parseSystemEventsLoginItems(
                "not json",
                bundleIdentifierForPath: { _ in nil }
            ).isEmpty
        )
    }

    func testRememberedDisabledLoginItemRemainsVisibleAndOff() throws {
        let suite = "AutoStartManagerTests-(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }

        let appURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("Remembered-(UUID().uuidString).app")
        try FileManager.default.createDirectory(
            at: appURL,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: appURL) }

        defaults.set(
            [appURL.path: "Remembered App"],
            forKey: AutoStartManager.disabledLoginItemsKey
        )

        let manager = AutoStartManager(
            defaults: defaults,
            loginItemProvider: { [] }
        )

        let items = manager.getLoginItems()
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0].name, "Remembered App")
        XCTAssertEqual(items[0].programPath, appURL.path)
        XCTAssertFalse(items[0].isEnabled)
        XCTAssertTrue(items[0].canToggle)
    }

    func testActiveLoginItemClearsStaleRememberedDisabledRecord() throws {
        let suite = "AutoStartManagerTests-(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }

        let appURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("Active-(UUID().uuidString).app")
        try FileManager.default.createDirectory(
            at: appURL,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: appURL) }

        defaults.set(
            [appURL.path: "Active App"],
            forKey: AutoStartManager.disabledLoginItemsKey
        )

        let active = AutoStartItem(
            name: "Active App",
            bundleIdentifier: "com.example.active",
            programPath: appURL.path,
            configFilePath: appURL.path,
            sourceType: .loginItem,
            isSystem: false,
            isEnabled: true
        )

        let manager = AutoStartManager(
            defaults: defaults,
            loginItemProvider: { [active] }
        )

        let items = manager.getLoginItems()
        XCTAssertEqual(items.count, 1)
        XCTAssertTrue(items[0].isEnabled)

        let remembered = defaults.dictionary(
            forKey: AutoStartManager.disabledLoginItemsKey
        ) as? [String: String]
        XCTAssertNil(remembered?[appURL.path])
    }

    func testSystemLaunchAgentCannotToggle() {
        let item = AutoStartItem(
            name: "System Agent",
            bundleIdentifier: "com.example.system",
            programPath: "/Library/Example",
            configFilePath: "/Library/LaunchAgents/com.example.system.plist",
            sourceType: .launchAgent,
            isSystem: true,
            isEnabled: true
        )

        XCTAssertFalse(item.canToggle)
    }
}
