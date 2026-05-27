import Foundation
import XCTest
@testable import TransactionClassifier

final class MatchAndClassifyViewsRequirementsTests: XCTestCase {
    func testLongListManualSelectionDoesNotRecenterInSmokeSuite() throws {
        // #R050-T01
        let source = try Self.loadUITestSource()
        XCTAssertTrue(
            source.contains("runLongListManualSelectionDoesNotRecenterScenario"),
            "Smoke suite must include long-list manual selection scroll stability scenario."
        )
    }

    func testAmountVariantsSupportCoffeeRoastersReceiptTotal() {
        // #R035-T02
        guard let amount = Decimal(string: "16.24") else {
            XCTFail("Expected valid decimal literal")
            return
        }
        let variants = amountSearchVariants(for: amount)
        XCTAssertTrue(variants.contains { $0.contains("16.24") })
    }
}

private extension MatchAndClassifyViewsRequirementsTests {
    static func loadUITestSource() throws -> String {
        let currentFile = URL(fileURLWithPath: #filePath)
        let packageRoot = currentFile
            .deletingLastPathComponent() // TransactionClassifierTests
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // macos-ui package root
        let uiTestFile = packageRoot
            .appendingPathComponent("UITests")
            .appendingPathComponent("TransactionClassifierUITests.swift")
        return try String(contentsOf: uiTestFile, encoding: .utf8)
    }
}
