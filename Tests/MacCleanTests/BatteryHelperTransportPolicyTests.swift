import XCTest
@testable import MacClean

final class BatteryHelperTransportPolicyTests: XCTestCase {
    func testLatestRefreshGenerationWins() {
        var sequencer = BatteryHelperRefreshSequencer()
        let first = sequencer.begin()
        let second = sequencer.begin()

        XCTAssertFalse(sequencer.isCurrent(first))
        XCTAssertTrue(sequencer.isCurrent(second))
    }

    func testInvalidateMakesOutstandingRefreshStale() {
        var sequencer = BatteryHelperRefreshSequencer()
        let token = sequencer.begin()
        sequencer.invalidate()

        XCTAssertFalse(sequencer.isCurrent(token))
    }

    func testTransportTimeoutIsBounded() {
        XCTAssertEqual(BatteryHelperTransportPolicy.responseTimeoutSeconds, 3.0)
    }

    func testExclusiveHelperActionsRefuseReentry() throws {
        let manager = try String(
            contentsOf: repoRoot.appending(
                path: "Sources/MacClean/Services/BatteryHardwareHelperManager.swift"
            ),
            encoding: .utf8
        )
        let view = try String(
            contentsOf: repoRoot.appending(
                path: "Sources/MacClean/Views/Battery/BatteryCareView.swift"
            ),
            encoding: .utf8
        )

        XCTAssertTrue(manager.contains("func register() async {\n        guard !isBusy else { return }"))
        XCTAssertTrue(manager.contains("func unregister() async {\n        guard !isBusy else { return }"))
        XCTAssertTrue(manager.contains("func reregister() async {\n        guard !isBusy else { return }"))
        XCTAssertTrue(manager.contains("func probeSameValueWrite() async {\n        guard !isBusy else { return }"))
        XCTAssertTrue(view.contains(".disabled(helperManager.isBusy)"))
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
        XCTAssertTrue(manager.contains("guard !isBusy else { return }"))
        XCTAssertTrue(manager.contains("refreshSequencer.invalidate()"))
        XCTAssertTrue(manager.contains("refreshSequencer.isCurrent(generation)"))
    }

    private var repoRoot: URL {
        URL(filePath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
