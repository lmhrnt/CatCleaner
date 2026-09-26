import XCTest
@testable import MacClean

final class BatteryHelperRegistrationRepairTests: XCTestCase {
    private enum ProbeError: Error {
        case unregister
        case register
    }

    func testRepairUnregistersBeforeRegister() throws {
        var events: [String] = []

        try BatteryHelperRegistrationRepair.perform(
            unregister: { events.append("unregister") },
            register: { events.append("register") }
        )

        XCTAssertEqual(events, ["unregister", "register"])
    }

    func testRepairDoesNotRegisterWhenUnregisterFails() {
        var registerWasCalled = false

        XCTAssertThrowsError(
            try BatteryHelperRegistrationRepair.perform(
                unregister: { throw ProbeError.unregister },
                register: { registerWasCalled = true }
            )
        ) { error in
            XCTAssertEqual(error as? ProbeError, .unregister)
        }

        XCTAssertFalse(registerWasCalled)
    }

    func testRepairPropagatesRegisterFailureAfterSuccessfulUnregister() {
        var unregisterWasCalled = false

        XCTAssertThrowsError(
            try BatteryHelperRegistrationRepair.perform(
                unregister: { unregisterWasCalled = true },
                register: { throw ProbeError.register }
            )
        ) { error in
            XCTAssertEqual(error as? ProbeError, .register)
        }

        XCTAssertTrue(unregisterWasCalled)
    }
}
