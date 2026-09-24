import Darwin
import Foundation
import MacCleanKit
import Security
import os

private let logger = Logger(
    subsystem: "com.catcleaner.app",
    category: "battery-helper"
)

private final class SigningPeerValidator {
    private let helperLeafCertificate: Data?

    init() {
        helperLeafCertificate = Self.leafCertificateDataForSelf()
    }

    func validate(_ connection: NSXPCConnection) -> Bool {
        guard connection.effectiveUserIdentifier != 0,
              let helperLeafCertificate,
              let clientCode = Self.code(forPID: connection.processIdentifier),
              SecCodeCheckValidity(
                clientCode,
                SecCSFlags(rawValue: kSecCSStrictValidate),
                nil
              ) == errSecSuccess,
              let info = Self.signingInfo(for: clientCode),
              info.identifier == MCConstants.bundleIdentifier,
              info.leafCertificate == helperLeafCertificate else {
            return false
        }
        return true
    }

    private struct SigningInfo {
        let identifier: String?
        let leafCertificate: Data?
    }

    private static func code(forPID pid: pid_t) -> SecCode? {
        let attributes = [
            kSecGuestAttributePid as String: NSNumber(value: pid)
        ] as CFDictionary

        var code: SecCode?
        guard SecCodeCopyGuestWithAttributes(
            nil,
            attributes,
            SecCSFlags(rawValue: 0),
            &code
        ) == errSecSuccess else {
            return nil
        }
        return code
    }

    private static func leafCertificateDataForSelf() -> Data? {
        var code: SecCode?
        guard SecCodeCopySelf(SecCSFlags(rawValue: 0), &code) == errSecSuccess,
              let code,
              let info = signingInfo(for: code) else {
            return nil
        }
        return info.leafCertificate
    }

    private static func signingInfo(for code: SecCode) -> SigningInfo? {
        var staticCode: SecStaticCode?
        guard SecCodeCopyStaticCode(
            code,
            SecCSFlags(rawValue: 0),
            &staticCode
        ) == errSecSuccess,
        let staticCode else {
            return nil
        }

        var rawInfo: CFDictionary?
        guard SecCodeCopySigningInformation(
            staticCode,
            SecCSFlags(rawValue: kSecCSSigningInformation),
            &rawInfo
        ) == errSecSuccess,
        let rawInfo else {
            return nil
        }

        let info = rawInfo as NSDictionary
        let identifier = info[kSecCodeInfoIdentifier as String] as? String

        var leafData: Data?
        if let certificates = info[kSecCodeInfoCertificates as String] as? [Any],
           let first = certificates.first {
            let certificate = first as! SecCertificate
            leafData = SecCertificateCopyData(certificate) as Data
        }

        return SigningInfo(
            identifier: identifier,
            leafCertificate: leafData
        )
    }
}

private enum TrustedSMCTool {
    static func locate() -> URL? {
        for rawPath in ["/usr/local/bin/smc", "/opt/homebrew/bin/smc", "/usr/bin/smc"] {
            let url = URL(filePath: rawPath).resolvingSymlinksInPath()
            guard isTrustedExecutable(url) else { continue }
            return url
        }
        return nil
    }

    private static func isTrustedExecutable(_ url: URL) -> Bool {
        let fileManager = FileManager.default
        guard fileManager.isExecutableFile(atPath: url.path),
              let attributes = try? fileManager.attributesOfItem(atPath: url.path),
              let type = attributes[.type] as? FileAttributeType,
              type == .typeRegular,
              let ownerID = attributes[.ownerAccountID] as? NSNumber,
              ownerID.uint32Value == 0,
              let permissions = attributes[.posixPermissions] as? NSNumber else {
            return false
        }

        // Root helper must never execute an SMC utility writable by group/other.
        return permissions.uint16Value & 0o022 == 0
    }
}

private enum CompetingController {
    private static let fragments = [
        "/Applications/AlDente.app/Contents/MacOS/AlDente",
        "/Library/PrivilegedHelperTools/com.apphousekitchen.aldente-pro.helper",
        "/Library/PrivilegedHelperTools/com.chenran.chargewatch.helper",
    ]

    static func isRunning() -> Bool {
        fragments.contains { fragment in
            let result = try? ProcessOutputCapture.run(
                executable: URL(filePath: "/usr/bin/pgrep"),
                arguments: ["-f", fragment]
            )
            return result?.exitCode == 0
        }
    }
}

private final class BatteryHelperService: NSObject, BatteryHelperXPCProtocol {
    private let clientValidated: Bool

    init(clientValidated: Bool) {
        self.clientValidated = clientValidated
    }

    func status(withReply reply: @escaping (NSDictionary) -> Void) {
        let tool = TrustedSMCTool.locate()
        var result: [String: Any] = [
            BatteryHelperResponseKey.ok: clientValidated && geteuid() == 0,
            BatteryHelperResponseKey.message: statusMessage(tool: tool),
            BatteryHelperResponseKey.helperEUID: Int(geteuid()),
            BatteryHelperResponseKey.helperPID: Int(getpid()),
            BatteryHelperResponseKey.clientValidated: clientValidated,
        ]
        if let tool {
            result[BatteryHelperResponseKey.smcToolPath] = tool.path
        }
        reply(result as NSDictionary)
    }

    func probeSameValueWrite(withReply reply: @escaping (NSDictionary) -> Void) {
        guard clientValidated else {
            reply(failure("呼叫端簽章驗證失敗"))
            return
        }
        guard geteuid() == 0 else {
            reply(failure("helper 不是以 root 身分執行"))
            return
        }
        guard !CompetingController.isRunning() else {
            reply(failure("偵測到其他電池控制器正在執行；依互斥政策拒絕 SMC 寫入探針"))
            return
        }
        guard let tool = TrustedSMCTool.locate() else {
            reply(failure("找不到 root 擁有且不可由一般使用者改寫的 smc 工具"))
            return
        }

        let key = BatteryHelperProbePolicy.fixedProbeKey
        guard let before = readHexByte(key: key, using: tool) else {
            reply(failure("無法讀取固定探針 key \(key)"))
            return
        }

        let write: ProcessOutputCaptureResult
        do {
            write = try ProcessOutputCapture.run(
                executable: tool,
                arguments: ["-k", key, "-w", before]
            )
        } catch {
            reply(failure("啟動 smc 同值寫回失敗：\(error.localizedDescription)"))
            return
        }

        guard let after = readHexByte(key: key, using: tool) else {
            reply(failure(
                "同值寫回後無法重新讀取 \(key)",
                before: before,
                writeExit: write.exitCode
            ))
            return
        }

        let equal = BatteryHelperProbePolicy.isSameValueProbe(
            before: before,
            after: after
        )
        let ok = write.exitCode == 0 && equal

        reply([
            BatteryHelperResponseKey.ok: ok,
            BatteryHelperResponseKey.message: ok
                ? "root 同值寫回／readback 探針通過；尚未授權任何實際電池狀態變更"
                : "root 同值寫回探針未通過；硬體控制維持鎖定",
            BatteryHelperResponseKey.helperEUID: Int(geteuid()),
            BatteryHelperResponseKey.helperPID: Int(getpid()),
            BatteryHelperResponseKey.clientValidated: true,
            BatteryHelperResponseKey.smcToolPath: tool.path,
            BatteryHelperResponseKey.beforeValue: before,
            BatteryHelperResponseKey.afterValue: after,
            BatteryHelperResponseKey.writeExitCode: Int(write.exitCode),
        ] as NSDictionary)
    }

    private func statusMessage(tool: URL?) -> String {
        guard clientValidated else { return "呼叫端簽章驗證失敗" }
        guard geteuid() == 0 else { return "helper 尚未以 root LaunchDaemon 身分執行" }
        guard tool != nil else { return "找不到受信任的 smc 工具" }
        if CompetingController.isRunning() {
            return "helper 已啟用，但偵測到其他電池控制器；寫入維持互斥鎖定"
        }
        return "helper 已以 root 執行，可進行零語意同值寫回能力探針"
    }

    private func readHexByte(key: String, using tool: URL) -> String? {
        guard let result = try? ProcessOutputCapture.run(
            executable: tool,
            arguments: ["-r", "-k", key]
        ),
        result.exitCode == 0 else {
            return nil
        }

        // Expected utility output includes a byte such as "00" or "01".
        // Search tokens conservatively instead of depending on one formatting
        // version of the third-party read-only utility.
        let tokens = (result.stdout + "\n" + result.stderr)
            .split { $0.isWhitespace || $0 == ":" || $0 == "=" || $0 == "," }
            .map(String.init)

        for token in tokens.reversed() {
            if let byte = BatteryHelperProbePolicy.normalizedHexByte(token) {
                return byte
            }
        }
        return nil
    }

    private func failure(
        _ message: String,
        before: String? = nil,
        writeExit: Int32? = nil
    ) -> NSDictionary {
        var result: [String: Any] = [
            BatteryHelperResponseKey.ok: false,
            BatteryHelperResponseKey.message: message,
            BatteryHelperResponseKey.helperEUID: Int(geteuid()),
            BatteryHelperResponseKey.helperPID: Int(getpid()),
            BatteryHelperResponseKey.clientValidated: clientValidated,
        ]
        if let before {
            result[BatteryHelperResponseKey.beforeValue] = before
        }
        if let writeExit {
            result[BatteryHelperResponseKey.writeExitCode] = Int(writeExit)
        }
        return result as NSDictionary
    }
}

private final class ListenerDelegate: NSObject, NSXPCListenerDelegate {
    private let validator = SigningPeerValidator()

    func listener(
        _ listener: NSXPCListener,
        shouldAcceptNewConnection newConnection: NSXPCConnection
    ) -> Bool {
        let validated = validator.validate(newConnection)
        guard validated else {
            logger.error(
                "Rejected XPC client pid=\(newConnection.processIdentifier, privacy: .public)"
            )
            return false
        }

        let service = BatteryHelperService(clientValidated: true)
        newConnection.exportedInterface = NSXPCInterface(
            with: BatteryHelperXPCProtocol.self
        )
        newConnection.exportedObject = service
        newConnection.resume()

        logger.log(
            "Accepted XPC client pid=\(newConnection.processIdentifier, privacy: .public)"
        )
        return true
    }
}

private func main() {
    let delegate = ListenerDelegate()
    let listener = NSXPCListener(
        machServiceName: MCConstants.batteryHelperMachServiceName
    )
    listener.delegate = delegate
    listener.resume()

    logger.log(
        "Battery helper first light pid=\(getpid(), privacy: .public) euid=\(geteuid(), privacy: .public)"
    )
    dispatchMain()
}

main()
