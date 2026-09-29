import XCTest
import ServiceManagement
@testable import MacClean

@MainActor
final class LaunchAtLoginManagerTests: XCTestCase {
    func testRefreshStatusReadsCurrentServiceStatus() {
        let serviceStatus = StatusBox(.notRegistered)
        let manager = makeManager(statusProvider: { serviceStatus.value })

        XCTAssertFalse(manager.refreshStatus())
        XCTAssertEqual(manager.status, .notRegistered)

        serviceStatus.value = .enabled

        XCTAssertTrue(manager.refreshStatus())
        XCTAssertEqual(manager.status, .enabled)
    }

    func testFailedRegisterReturnsActualDisabledStatus() async {
        let manager = makeManager(
            statusProvider: { .notRegistered },
            registrationUpdater: { enabled in enabled ? "registration denied" : nil }
        )

        let actualValue = await manager.setEnabled(true)

        XCTAssertFalse(actualValue)
        XCTAssertEqual(manager.status, .notRegistered)
        XCTAssertNotNil(manager.lastError)
    }

    func testFailedUnregisterReturnsActualEnabledStatus() async {
        let manager = makeManager(
            statusProvider: { .enabled },
            registrationUpdater: { enabled in enabled ? nil : "unregister denied" }
        )

        let actualValue = await manager.setEnabled(false)

        XCTAssertTrue(actualValue)
        XCTAssertEqual(manager.status, .enabled)
        XCTAssertNotNil(manager.lastError)
    }

    func testOverlappingSetEnabledCallsRunOnlyOneRegistrationUpdate() async {
        let counter = LockedCounter()
        let manager = makeManager(
            statusProvider: { .notRegistered },
            registrationUpdater: { _ in
                counter.increment()
                Thread.sleep(forTimeInterval: 0.15)
                return nil
            }
        )

        let first = Task { await manager.setEnabled(true) }
        await Task.yield()
        let secondResult = await manager.setEnabled(false)
        _ = await first.value

        XCTAssertFalse(secondResult)
        XCTAssertEqual(counter.value, 1)
        XCTAssertFalse(manager.isBusy)
    }

    private func makeManager(
        statusProvider: @escaping @MainActor () -> SMAppService.Status,
        registrationUpdater: @escaping @Sendable (Bool) -> String? = { _ in nil }
    ) -> LaunchAtLoginManager {
        LaunchAtLoginManager(
            statusProvider: statusProvider,
            registrationUpdater: registrationUpdater,
            minimumBusyDuration: .zero
        )
    }

    @MainActor
    private final class StatusBox {
        var value: SMAppService.Status

        init(_ value: SMAppService.Status) {
            self.value = value
        }
    }

    private final class LockedCounter: @unchecked Sendable {
        private let lock = NSLock()
        private var count = 0

        func increment() {
            lock.lock()
            count += 1
            lock.unlock()
        }

        var value: Int {
            lock.lock()
            defer { lock.unlock() }
            return count
        }
    }
}
