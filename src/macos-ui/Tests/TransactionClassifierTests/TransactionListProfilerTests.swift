import XCTest
@testable import TransactionClassifier

final class TransactionListProfilerTests: XCTestCase {
    func testProfilerDisabledByDefault() {
        XCTAssertFalse(TransactionListProfiler.isEnabled)
    }
}
