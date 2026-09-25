import Foundation
import XCTest

final class BatteryHelperSecurityContractTests: XCTestCase {
    private var repoRoot: URL {
        URL(filePath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func source(_ relativePath: String) throws -> String {
        try String(
            contentsOf: repoRoot.appending(path: relativePath),
            encoding: .utf8
        )
    }

    func testHelperRPCDoesNotExposeArbitraryKeyOrValueParameters() throws {
        let contract = try source("Sources/MacCleanKit/BatteryHelperXPC.swift")
        let start = try XCTUnwrap(
            contract.range(of: "@objc public protocol BatteryHelperXPCProtocol {")
        )
        let remainder = contract[start.lowerBound...]
        let end = try XCTUnwrap(remainder.range(of: "\n}"))
        let protocolBlock = String(remainder[..<end.upperBound])

        XCTAssertTrue(protocolBlock.contains(
            "func status(withReply reply: @escaping (NSDictionary) -> Void)"
        ))
        XCTAssertTrue(protocolBlock.contains(
            "func probeSameValueWrite(withReply reply: @escaping (NSDictionary) -> Void)"
        ))
        XCTAssertEqual(protocolBlock.components(separatedBy: "func ").count - 1, 2)
        XCTAssertFalse(protocolBlock.contains("key:"))
        XCTAssertFalse(protocolBlock.contains("value:"))
        XCTAssertFalse(protocolBlock.contains("writeKey"))
        XCTAssertFalse(protocolBlock.contains("setKey"))
    }

    func testHelperValidatesCatCleanerClientIdentityAndSameCertificate() throws {
        let helper = try source("Sources/CatCleanerBatteryHelper/main.swift")

        XCTAssertTrue(helper.contains("newConnection.processIdentifier"))
        XCTAssertTrue(helper.contains("SecCodeCopyGuestWithAttributes"))
        XCTAssertTrue(helper.contains("info.identifier == MCConstants.bundleIdentifier"))
        XCTAssertTrue(helper.contains("info.leafCertificate == helperLeafCertificate"))
        XCTAssertTrue(helper.contains("kSecCSStrictValidate"))
        XCTAssertTrue(helper.contains("com.catcleaner.battery-helper.signing-validation"))
        XCTAssertTrue(helper.contains("SigningValidationState"))
        XCTAssertTrue(helper.contains("ValidationResultBox"))
        XCTAssertTrue(helper.contains("validationQueue.async"))
        XCTAssertTrue(helper.contains("DispatchSemaphore(value: 0)"))
        XCTAssertTrue(helper.contains("effectiveUserIdentifier: uid"))
        XCTAssertTrue(helper.contains("processIdentifier: pid"))
        XCTAssertFalse(helper.contains("validationQueue.sync"))
        XCTAssertFalse(helper.contains("validator.validate(newConnection)"))
    }

    func testHelperRefusesCompetingBatteryControllers() throws {
        let helper = try source("Sources/CatCleanerBatteryHelper/main.swift")

        XCTAssertTrue(helper.contains("CompetingController.isRunning()"))
        XCTAssertTrue(helper.contains("com.apphousekitchen.aldente-pro.helper"))
        XCTAssertTrue(helper.contains("依互斥政策拒絕 SMC 寫入探針"))
    }

    func testHelperOnlyUsesFixedSameValueProbe() throws {
        let helper = try source("Sources/CatCleanerBatteryHelper/main.swift")

        XCTAssertTrue(helper.contains("BatteryHelperProbePolicy.fixedProbeKey"))
        XCTAssertTrue(helper.contains(#"arguments: ["-k", key, "-w", before]"#))
        XCTAssertTrue(helper.contains("BatteryHelperProbePolicy.isSameValueProbe"))
        XCTAssertFalse(helper.contains("CommandLine.arguments"))
        XCTAssertFalse(helper.contains("ProcessInfo.processInfo.arguments"))
    }

    func testBuildAndSigningScriptsEnforceServiceManagementDaemon() throws {
        let buildScript = try source("scripts/build-dmg.sh")
        let signingScript = try source("scripts/local-signing-identity.sh")
        let verifier = try source("scripts/verify-app-bundle.sh")

        XCTAssertTrue(buildScript.contains("--product CatCleanerBatteryHelper"))
        XCTAssertTrue(buildScript.contains("Contents/Library/LaunchDaemons"))
        XCTAssertTrue(buildScript.contains("<key>BundleProgram</key>"))
        XCTAssertTrue(
            buildScript.contains("<string>Contents/MacOS/CatCleanerBatteryHelper</string>")
        )
        XCTAssertTrue(buildScript.contains("<key>com.catcleaner.battery-helper</key>"))

        XCTAssertTrue(signingScript.contains("local battery_helper="))
        XCTAssertTrue(signingScript.contains("unexpected battery helper signing authority"))
        XCTAssertTrue(signingScript.contains(#"codesign --verify --strict "$battery_helper""#))

        XCTAssertTrue(verifier.contains("BATTERY_HELPER="))
        XCTAssertTrue(verifier.contains("BATTERY_PLIST="))
        XCTAssertTrue(verifier.contains("battery_helper_archs="))
        XCTAssertTrue(verifier.contains("Print :BundleProgram"))
        XCTAssertTrue(verifier.contains("Print :MachServices:com.catcleaner.battery-helper"))
    }
}
