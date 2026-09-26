import Foundation
import Observation
import ServiceManagement
import MacCleanKit

enum BatteryHelperRegistrationRepair {
    static func perform(
        unregister: () throws -> Void,
        register: () throws -> Void
    ) throws {
        try unregister()
        try register()
    }
}

@MainActor
@Observable
final class BatteryHardwareHelperManager {
    static let shared = BatteryHardwareHelperManager()

    private let service = SMAppService.daemon(
        plistName: MCConstants.batteryHelperLaunchDaemonPlistName
    )

    private(set) var status: SMAppService.Status = .notRegistered
    private(set) var isBusy = false
    private(set) var helperStatusMessage = "尚未查詢 helper"
    private(set) var lastProbeMessage: String?
    private(set) var lastProbePassed = false

    private init() {
        status = service.status
    }

    var statusText: String {
        switch status {
        case .notRegistered: "尚未註冊"
        case .enabled: "已啟用"
        case .requiresApproval: "等待系統核准"
        case .notFound: "App 內找不到 helper"
        @unknown default: "未知狀態"
        }
    }

    var canProbe: Bool {
        status == .enabled
    }

    func refresh() async {
        status = service.status
        guard status == .enabled else {
            helperStatusMessage = "helper \(statusText)"
            lastProbePassed = false
            return
        }

        let response = await callHelper { proxy, reply in
            proxy.status(withReply: reply)
        }
        applyStatus(response)
    }

    func register() async {
        isBusy = true
        defer { isBusy = false }

        let errorMessage: String? = await Task.detached(priority: .userInitiated) {
            let service = SMAppService.daemon(
                plistName: MCConstants.batteryHelperLaunchDaemonPlistName
            )
            do {
                try service.register()
                return nil
            } catch {
                return error.localizedDescription
            }
        }.value

        status = service.status
        if let errorMessage {
            helperStatusMessage = "註冊結果：" + errorMessage
        } else {
            helperStatusMessage = "helper 註冊要求已送出"
        }

        if status == .enabled {
            await refresh()
        }
    }

    func unregister() async {
        isBusy = true
        defer { isBusy = false }

        let errorMessage: String? = await Task.detached(priority: .userInitiated) {
            let service = SMAppService.daemon(
                plistName: MCConstants.batteryHelperLaunchDaemonPlistName
            )
            do {
                try service.unregister()
                return nil
            } catch {
                return error.localizedDescription
            }
        }.value

        status = service.status
        if let errorMessage {
            helperStatusMessage = "停用結果：" + errorMessage
        } else {
            helperStatusMessage = "helper 已停用"
        }
        lastProbePassed = false
        lastProbeMessage = nil
    }

    func reregister() async {
        isBusy = true
        defer { isBusy = false }

        let errorMessage: String? = await Task.detached(priority: .userInitiated) {
            let service = SMAppService.daemon(
                plistName: MCConstants.batteryHelperLaunchDaemonPlistName
            )
            do {
                try BatteryHelperRegistrationRepair.perform(
                    unregister: { try service.unregister() },
                    register: { try service.register() }
                )
                return nil
            } catch {
                return error.localizedDescription
            }
        }.value

        status = service.status
        lastProbePassed = false
        lastProbeMessage = nil

        if let errorMessage {
            helperStatusMessage = "重新註冊結果：" + errorMessage
            return
        }

        helperStatusMessage = "helper 重新註冊要求已送出"
        if status == .enabled {
            await refresh()
        }
    }

    func openApprovalSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }

    func probeSameValueWrite() async {
        guard status == .enabled else {
            lastProbePassed = false
            lastProbeMessage = "helper 尚未啟用"
            return
        }

        isBusy = true
        defer { isBusy = false }

        let response = await callHelper { proxy, reply in
            proxy.probeSameValueWrite(withReply: reply)
        }

        lastProbePassed = response.ok
        lastProbeMessage = response.message
        helperStatusMessage = response.message
    }

    private func applyStatus(_ response: BatteryHelperReply) {
        helperStatusMessage = response.message

        // A status check never proves SMC write capability.
        if !response.ok {
            lastProbePassed = false
        }
    }

    private func callHelper(
        _ invoke: @escaping (
            BatteryHelperXPCProtocol,
            @escaping (NSDictionary) -> Void
        ) -> Void
    ) async -> BatteryHelperReply {
        await withCheckedContinuation { continuation in
            let connection = NSXPCConnection(
                machServiceName: MCConstants.batteryHelperMachServiceName,
                options: .privileged
            )
            connection.remoteObjectInterface = NSXPCInterface(
                with: BatteryHelperXPCProtocol.self
            )

            let once = ContinuationOnce(continuation)
            connection.interruptionHandler = {
                once.resume(.failure("helper XPC 連線中斷"))
                connection.invalidate()
            }
            connection.invalidationHandler = {
                once.resume(.failure("helper XPC 連線失效"))
            }
            connection.resume()

            guard let proxy = connection.remoteObjectProxyWithErrorHandler({ error in
                once.resume(.failure(error.localizedDescription))
                connection.invalidate()
            }) as? BatteryHelperXPCProtocol else {
                once.resume(.failure("無法建立 helper XPC proxy"))
                connection.invalidate()
                return
            }

            invoke(proxy) { dictionary in
                once.resume(BatteryHelperReply(dictionary))
                connection.invalidate()
            }
        }
    }
}

private struct BatteryHelperReply: Sendable {
    let ok: Bool
    let message: String
    let helperEUID: Int?
    let helperPID: Int?
    let clientValidated: Bool?
    let smcToolPath: String?
    let beforeValue: String?
    let afterValue: String?
    let writeExitCode: Int?

    init(_ dictionary: NSDictionary) {
        ok = dictionary[BatteryHelperResponseKey.ok] as? Bool ?? false
        message = dictionary[BatteryHelperResponseKey.message] as? String
            ?? "helper 沒有回傳訊息"
        helperEUID = dictionary[BatteryHelperResponseKey.helperEUID] as? Int
        helperPID = dictionary[BatteryHelperResponseKey.helperPID] as? Int
        clientValidated = dictionary[BatteryHelperResponseKey.clientValidated] as? Bool
        smcToolPath = dictionary[BatteryHelperResponseKey.smcToolPath] as? String
        beforeValue = dictionary[BatteryHelperResponseKey.beforeValue] as? String
        afterValue = dictionary[BatteryHelperResponseKey.afterValue] as? String
        writeExitCode = dictionary[BatteryHelperResponseKey.writeExitCode] as? Int
    }

    static func failure(_ message: String) -> Self {
        Self(
            ok: false,
            message: message,
            helperEUID: nil,
            helperPID: nil,
            clientValidated: nil,
            smcToolPath: nil,
            beforeValue: nil,
            afterValue: nil,
            writeExitCode: nil
        )
    }

    private init(
        ok: Bool,
        message: String,
        helperEUID: Int?,
        helperPID: Int?,
        clientValidated: Bool?,
        smcToolPath: String?,
        beforeValue: String?,
        afterValue: String?,
        writeExitCode: Int?
    ) {
        self.ok = ok
        self.message = message
        self.helperEUID = helperEUID
        self.helperPID = helperPID
        self.clientValidated = clientValidated
        self.smcToolPath = smcToolPath
        self.beforeValue = beforeValue
        self.afterValue = afterValue
        self.writeExitCode = writeExitCode
    }
}

private final class ContinuationOnce: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<BatteryHelperReply, Never>?

    init(_ continuation: CheckedContinuation<BatteryHelperReply, Never>) {
        self.continuation = continuation
    }

    func resume(_ value: BatteryHelperReply) {
        lock.lock()
        guard let continuation else {
            lock.unlock()
            return
        }
        self.continuation = nil
        lock.unlock()
        continuation.resume(returning: value)
    }
}
