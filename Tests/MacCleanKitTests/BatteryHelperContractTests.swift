import XCTest
@testable import MacCleanKit

final class BatteryHelperContractTests: XCTestCase {
    func testProbeKeyIsFixedAndNotCallerControlled() {
        XCTAssertEqual(BatteryHelperProbePolicy.fixedProbeKey, "CHIE")
    }

    func testSameValueProbeRequiresExactNormalizedByteEquality() {
        XCTAssertTrue(
            BatteryHelperProbePolicy.isSameValueProbe(
                before: "00",
                after: "0x00"
            )
        )
        XCTAssertFalse(
            BatteryHelperProbePolicy.isSameValueProbe(
                before: "00",
                after: "01"
            )
        )
    }

    func testHexByteNormalizationRejectsNonByteInput() {
        XCTAssertEqual(BatteryHelperProbePolicy.normalizedHexByte("0x0A"), "0a")
        XCTAssertEqual(BatteryHelperProbePolicy.normalizedHexByte("ff"), "ff")
        XCTAssertEqual(BatteryHelperProbePolicy.normalizedHexByte("00)"), "00")
        XCTAssertEqual(BatteryHelperProbePolicy.normalizedHexByte("(0x0A)"), "0a")
        XCTAssertNil(BatteryHelperProbePolicy.normalizedHexByte(""))
        XCTAssertNil(BatteryHelperProbePolicy.normalizedHexByte("0000"))
        XCTAssertNil(BatteryHelperProbePolicy.normalizedHexByte("GG"))
    }

    func testMachServiceAndDaemonNamesAreCatCleanerScoped() {
        XCTAssertEqual(
            MCConstants.batteryHelperMachServiceName,
            "com.catcleaner.battery-helper"
        )
        XCTAssertEqual(
            MCConstants.batteryHelperLaunchDaemonPlistName,
            "com.catcleaner.battery-helper.plist"
        )
        XCTAssertEqual(
            MCConstants.batteryHelperExecutableName,
            "CatCleanerBatteryHelper"
        )
    }
}
