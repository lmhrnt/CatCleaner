import XCTest
@testable import MacCleanKit

final class NonOverlappingOperationGateTests: XCTestCase {
    func testRejectsSameKeyUntilReleased() {
        let gate = NonOverlappingOperationGate<String>()

        XCTAssertTrue(gate.begin("stats"))
        XCTAssertFalse(gate.begin("stats"))
        gate.end("stats")
        XCTAssertTrue(gate.begin("stats"))
    }

    func testDifferentKeysDoNotBlockEachOther() {
        let gate = NonOverlappingOperationGate<String>()

        XCTAssertTrue(gate.begin("stats"))
        XCTAssertTrue(gate.begin("network"))
    }

    func testConcurrentBeginAllowsExactlyOneWinnerPerKey() async {
        let gate = NonOverlappingOperationGate<String>()

        let winners = await withTaskGroup(of: Bool.self, returning: Int.self) { group in
            for _ in 0..<64 {
                group.addTask { gate.begin("devices") }
            }

            var count = 0
            for await acquired in group where acquired {
                count += 1
            }
            return count
        }

        XCTAssertEqual(winners, 1)
    }
}
