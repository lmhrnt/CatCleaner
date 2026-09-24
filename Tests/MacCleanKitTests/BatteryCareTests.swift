import XCTest
@testable import MacCleanKit

final class BatteryCareTests: XCTestCase {
    func testMenuBarStylesResolveStably() {
        for style in BatteryCareMenuBarStyle.allCases {
            XCTAssertEqual(BatteryCareMenuBarStyle.resolve(style.rawValue), style)
        }
        XCTAssertEqual(BatteryCareMenuBarStyle.resolve("unknown"), .battery)
        XCTAssertEqual(BatteryCareMenuBarStyle.resolve(nil), .battery)
    }

    func testChargeLimitIsClampedToSafeUserRange() {
        XCTAssertEqual(BatteryCarePolicy.clampedChargeLimit(10), 20)
        XCTAssertEqual(BatteryCarePolicy.clampedChargeLimit(80), 80)
        XCTAssertEqual(BatteryCarePolicy.clampedChargeLimit(120), 100)
    }

    func testHeatProtectionPausesAtThresholdButNotBelowFifteenPercent() {
        XCTAssertTrue(
            BatteryCarePolicy.shouldPauseCharging(
                levelPercent: 70,
                chargeLimit: 80,
                temperatureCelsius: 36,
                heatProtectionEnabled: true,
                heatLimitCelsius: 35
            )
        )
        XCTAssertFalse(
            BatteryCarePolicy.shouldPauseCharging(
                levelPercent: 10,
                chargeLimit: 80,
                temperatureCelsius: 40,
                heatProtectionEnabled: true,
                heatLimitCelsius: 35
            )
        )
    }

    func testChargeLimitAlwaysPausesAtOrAboveTarget() {
        XCTAssertTrue(
            BatteryCarePolicy.shouldPauseCharging(
                levelPercent: 80,
                chargeLimit: 80,
                temperatureCelsius: nil,
                heatProtectionEnabled: false,
                heatLimitCelsius: 35
            )
        )
        XCTAssertFalse(
            BatteryCarePolicy.shouldPauseCharging(
                levelPercent: 79,
                chargeLimit: 80,
                temperatureCelsius: nil,
                heatProtectionEnabled: false,
                heatLimitCelsius: 35
            )
        )
    }

    func testSailingModeWaitsForLowerBoundaryBeforeResuming() {
        XCTAssertFalse(
            BatteryCarePolicy.shouldResumeCharging(
                levelPercent: 79,
                chargeLimit: 80,
                sailingEnabled: true,
                sailingRange: 5
            )
        )
        XCTAssertTrue(
            BatteryCarePolicy.shouldResumeCharging(
                levelPercent: 75,
                chargeLimit: 80,
                sailingEnabled: true,
                sailingRange: 5
            )
        )
    }

    func testAutomaticDischargeRequiresACAndBatteryAboveTarget() {
        XCTAssertTrue(
            BatteryCarePolicy.shouldAutomaticallyDischarge(
                levelPercent: 90,
                chargeLimit: 80,
                automaticDischargeEnabled: true,
                externalPowerConnected: true
            )
        )
        XCTAssertFalse(
            BatteryCarePolicy.shouldAutomaticallyDischarge(
                levelPercent: 90,
                chargeLimit: 80,
                automaticDischargeEnabled: true,
                externalPowerConnected: false
            )
        )
        XCTAssertFalse(
            BatteryCarePolicy.shouldAutomaticallyDischarge(
                levelPercent: 80,
                chargeLimit: 80,
                automaticDischargeEnabled: true,
                externalPowerConnected: true
            )
        )
    }

    func testHardwareWriteFeaturesAreExplicitlySeparatedFromUICustomization() {
        XCTAssertTrue(BatteryCareAction.chargeLimiter.requiresHardwareWrite)
        XCTAssertTrue(BatteryCareAction.calibration.requiresHardwareWrite)
        XCTAssertFalse(BatteryCareAction.shortcuts.requiresHardwareWrite)
        XCTAssertFalse(BatteryCareAction.menuBarCustomization.requiresHardwareWrite)
        XCTAssertFalse(BatteryCareAction.popupCustomization.requiresHardwareWrite)
    }

    func testBatteryHelperProbeIsFixedToOneByteSameValueSemantics() {
        XCTAssertEqual(BatteryHelperProbePolicy.fixedProbeKey, "CHIE")
        XCTAssertEqual(BatteryHelperProbePolicy.normalizedHexByte("00"), "00")
        XCTAssertEqual(BatteryHelperProbePolicy.normalizedHexByte("0x01"), "01")
        XCTAssertNil(BatteryHelperProbePolicy.normalizedHexByte("0000"))
        XCTAssertNil(BatteryHelperProbePolicy.normalizedHexByte("GG"))
        XCTAssertTrue(BatteryHelperProbePolicy.isSameValueProbe(before: "00", after: "0x00"))
        XCTAssertFalse(BatteryHelperProbePolicy.isSameValueProbe(before: "00", after: "01"))
    }
}
