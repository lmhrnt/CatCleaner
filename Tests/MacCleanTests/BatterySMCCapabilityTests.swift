import XCTest
@testable import MacClean
import MacCleanKit

final class BatterySMCCapabilityTests: XCTestCase {
    func testTahoeFamilyEnablesLimitInhibitAndDischarge() {
        let report = SMCCapabilityReport(existingKeys: ["CHTE", "CHIE", "CHSC"])

        XCTAssertEqual(report.controlFamily, "新式 Apple Silicon（CHTE／CHIE）")
        XCTAssertTrue(report.capabilities.contains(.chargeLimit))
        XCTAssertTrue(report.capabilities.contains(.inhibitCharge))
        XCTAssertTrue(report.capabilities.contains(.forceDischarge))
    }

    func testLegacyFamilyEnablesLimitInhibitAndDischarge() {
        let report = SMCCapabilityReport(existingKeys: ["CH0B", "CH0C", "CH0I"])

        XCTAssertEqual(report.controlFamily, "傳統 Apple Silicon（CH0B／CH0C／CH0I）")
        XCTAssertTrue(report.capabilities.contains(.chargeLimit))
        XCTAssertTrue(report.capabilities.contains(.inhibitCharge))
        XCTAssertTrue(report.capabilities.contains(.forceDischarge))
    }

    func testMagSafeLEDKeyEnablesLEDControlCapability() {
        let report = SMCCapabilityReport(existingKeys: ["CHTE", "CHIE", "ACLC"])

        XCTAssertTrue(report.capabilities.contains(.magsafeLED))
    }

    func testFirmwareFamilyTakesPrecedence() {
        let report = SMCCapabilityReport(
            existingKeys: ["bfD0", "bfE0", "bfF0", "CHTE", "CHIE"]
        )

        XCTAssertEqual(report.controlFamily, "macOS 27 韌體充電上限")
        XCTAssertTrue(report.capabilities.contains(.chargeLimit))
    }

    func testFirmwareVersionComparisonPadsMissingComponents() throws {
        let current = try XCTUnwrap(FirmwareVersion("mBoot-20457.1.29"))
        let blockedSince = try XCTUnwrap(FirmwareVersion("20457.0.125.0.2"))
        let older = try XCTUnwrap(FirmwareVersion("20457.0.77.0.2"))

        XCTAssertGreaterThan(current, blockedSince)
        XCTAssertLessThan(older, blockedSince)
        XCTAssertEqual(
            FirmwareVersion("20457.1"),
            FirmwareVersion("20457.1.0.0")
        )
    }

    func testKnownMacOS27FirmwareIsBlockedForDirectSMCWrites() {
        XCTAssertEqual(
            BatteryFirmwarePolicy.directSMCWriteDisposition(
                firmwareVersion: "mBoot-20457.1.29"
            ),
            .knownBlocked
        )
        XCTAssertEqual(
            BatteryFirmwarePolicy.directSMCWriteDisposition(
                firmwareVersion: "20457.0.125.0.2"
            ),
            .knownBlocked
        )
        XCTAssertEqual(
            BatteryFirmwarePolicy.directSMCWriteDisposition(
                firmwareVersion: "20457.0.77.0.2"
            ),
            .candidate
        )
        XCTAssertEqual(
            BatteryFirmwarePolicy.directSMCWriteDisposition(firmwareVersion: nil),
            .unknown
        )
    }
}
