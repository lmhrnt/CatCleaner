import XCTest
@testable import MacClean

final class BatteryHelperTransportPolicyTests: XCTestCase {
    func testTransportTimeoutIsBounded() {
        XCTAssertEqual(BatteryHelperTransportPolicy.responseTimeoutSeconds, 3.0)
    }

    func testEnabledServiceNeedsRepairWhenTransportIsUnavailable() {
        XCTAssertTrue(
            BatteryHelperTransportPolicy.needsRegistrationRepair(
                serviceEnabled: true,
                transportAvailable: false
            )
        )
    }

    func testEnabledServiceDoesNotNeedRepairWhenTransportResponds() {
        XCTAssertFalse(
            BatteryHelperTransportPolicy.needsRegistrationRepair(
                serviceEnabled: true,
                transportAvailable: true
            )
        )
    }

    func testDisabledServiceDoesNotReportStaleRegistration() {
        XCTAssertFalse(
            BatteryHelperTransportPolicy.needsRegistrationRepair(
                serviceEnabled: false,
                transportAvailable: false
            )
        )
    }

    func testNormalNegativeHelperReplyMustNotBeTreatedAsTransportFailure() throws {
        let manager = try String(
            contentsOf: repoRoot.appending(
                path: "Sources/MacClean/Services/BatteryHardwareHelperManager.swift"
            ),
            encoding: .utf8
        )

        XCTAssertTrue(manager.contains("transportAvailable = true"))
        XCTAssertTrue(manager.contains("transportAvailable: false"))
        XCTAssertTrue(manager.contains("repairAwareMessage(response)"))
        XCTAssertTrue(manager.contains("guard !needsRegistrationRepair else"))
        XCTAssertTrue(manager.contains("helper XPC 連線逾時"))
        XCTAssertTrue(manager.contains("XPCConnectionLifetime"))
        XCTAssertTrue(manager.contains("asyncAfter"))
    }

    private var repoRoot: URL {
        URL(filePath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
