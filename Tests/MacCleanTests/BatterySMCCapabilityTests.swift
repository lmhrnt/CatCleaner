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
}
