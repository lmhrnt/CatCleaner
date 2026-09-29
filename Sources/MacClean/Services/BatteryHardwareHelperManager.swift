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

enum BatteryHelperTransportPolicy {
    static let responseTimeoutSeconds: Double = 3.0

    static func needsRegistrationRepair(
        serviceEnabled: Bool,
        transportAvailable: Bool
    ) -> Bool {
        serviceEnabled && !transportAvailable
    }
}

struct BatteryHelperRefreshSequencer {
    private(set) var generation: UInt64 = 0

    mutating func begin() -> UInt64 {
        generation &+= 1
        return generation
    }

    mutating func invalidate() {
        generation &+= 1
    }

    func isCurrent(_ token: UInt64) -> Bool {
        token == generation
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
    private(set) var needsRegistrationRepair = false
    private var refreshSequencer = BatteryHelperRefreshSequencer()

    private init() {
        status = service.status
    }

    var statusText: String {
        if needsRegistrationRepair, status == .enabled {
            return "需要修復"
        }

        switch status {
        case .notRegistered: return "尚未註冊"
        case .enabled: return "已啟用"
        case .requiresApproval: return "等待系統核准"
        case .notFound: return "App 內找不到 helper"
        @unknown default: return "未知狀態"
        }
    }

    var canProbe: Bool {
        status == .enabled && !needsRegistrationRepair
    }

    func refresh() async {
        guard !isBusy else { return }
        await refreshCurrentState()
    }

    private func refreshCurrentState() async {
        let generation = refreshSequencer.begin()
        status = service.status
        guard status == .enabled else {
            guard refreshSequencer.isCurrent(generation) else { return }
            helperStatusMessage = "helper \(statusText)"
            lastProbePassed = false
            lastProbeMessage = nil
            needsRegistrationRepair = false
            return
        }

        let response = await callHelper { proxy, reply in
            proxy.status(withReply: reply)
        }
        guard refreshSequencer.isCurrent(generation) else { return }
        applyStatus(response)
    }

    func register() async {
        guard !isBusy else { return }
        isBusy = true
        refreshSequencer.invalidate()
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
            await refreshCurrentState()
        }
    }

    func unregister() async {
        guard !isBusy else { return }
        isBusy = true
        refreshSequencer.invalidate()
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
        needsRegistrationRepair = false
    }

    func reregister() async {
        guard !isBusy else { return }
        isBusy = true
        refreshSequencer.invalidate()
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
            needsRegistrationRepair = status == .enabled
            helperStatusMessage = "重新註冊結果：" + errorMessage
            return
        }

        needsRegistrationRepair = false
        helperStatusMessage = "helper 重新註冊要求已送出"
        if status == .enabled {
            await refreshCurrentState()
        }
    }

    func openApprovalSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }

    func probeSameValueWrite() async {
        guard !isBusy else { return }
        guard status == .enabled else {
            lastProbePassed = false
            lastProbeMessage = "helper 尚未啟用"
            needsRegistrationRepair = false
            return
        }
        guard !needsRegistrationRepair else {
            lastProbePassed = false
            lastProbeMessage = "helper 需要重新註冊"
            helperStatusMessage = "helper XPC 無法連線；請重新註冊 helper"
            return
        }

        isBusy = true
        refreshSequencer.invalidate()
        defer { isBusy = false }

        let response = await callHelper { proxy, reply in
            proxy.probeSameValueWrite(withReply: reply)
        }

        needsRegistrationRepair = BatteryHelperTransportPolicy.needsRegistrationRepair(
            serviceEnabled: status == .enabled,
            transportAvailable: response.transportAvailable
        )
        lastProbePassed = response.ok
        lastProbeMessage = response.message
        helperStatusMessage = repairAwareMessage(response)
    }

    private func applyStatus(_ response: BatteryHelperReply) {
        needsRegistrationRepair = BatteryHelperTransportPolicy.needsRegistrationRepair(
            serviceEnabled: status == .enabled,
            transportAvailable: response.transportAvailable
        )
        helperStatusMessage = repairAwareMessage(response)

        // A status check never proves SMC write capability.
        if needsRegistrationRepair {
            lastProbePassed = false
            lastProbeMessage = nil
        } else if !response.ok {
            lastProbePassed = false
        }
    }

    private func repairAwareMessage(_ response: BatteryHelperReply) -> String {
        guard needsRegistrationRepair else { return response.message }
        return response.message + "；請重新註冊 helper"
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
            let lifetime = XPCConnectionLifetime(connection)

            DispatchQueue.global(qos: .userInitiated).asyncAfter(
                deadline: .now() + BatteryHelperTransportPolicy.responseTimeoutSeconds
            ) {
                once.resume(.failure("helper XPC 連線逾時"))
                lifetime.invalidate()
            }

            connection.interruptionHandler = {
                once.resume(.failure("helper XPC 連線中斷"))
                lifetime.invalidate()
            }
            connection.invalidationHandler = {
                once.resume(.failure("helper XPC 連線失效"))
            }
            connection.resume()

            guard let proxy = connection.remoteObjectProxyWithErrorHandler({ error in
                once.resume(.failure(error.localizedDescription))
                lifetime.invalidate()
            }) as? BatteryHelperXPCProtocol else {
                once.resume(.failure("無法建立 helper XPC proxy"))
                lifetime.invalidate()
                return
            }

            invoke(proxy) { dictionary in
                once.resume(BatteryHelperReply(dictionary))
                lifetime.invalidate()
            }
        }
    }
}

private struct BatteryHelperReply: Sendable {
    let ok: Bool
    let message: String
    let transportAvailable: Bool
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
        transportAvailable = true
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
            transportAvailable: false,
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
        transportAvailable: Bool,
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
        self.transportAvailable = transportAvailable
        self.helperEUID = helperEUID
        self.helperPID = helperPID
        self.clientValidated = clientValidated
        self.smcToolPath = smcToolPath
        self.beforeValue = beforeValue
        self.afterValue = afterValue
        self.writeExitCode = writeExitCode
    }
}

private final class XPCConnectionLifetime: @unchecked Sendable {
    private let lock = NSLock()
    private var connection: NSXPCConnection?

    init(_ connection: NSXPCConnection) {
        self.connection = connection
    }

    func invalidate() {
        lock.lock()
        let connection = self.connection
        self.connection = nil
        lock.unlock()
        connection?.invalidate()
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
