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

    func testCandidatesPaneUsesTransactionEmailMatchCandidatesHeading() throws {
        // #R066-T01
        let source = try Self.loadViewSource()
        XCTAssertTrue(
            source.contains(#"Text("Transaction - Email Match Candidates")"#),
            "Candidates pane must use Transaction - Email Match Candidates heading."
        )
    }

    func testClassifySectionUsesTransactionClassificationHeading() throws {
        // #R067-T01
        let source = try Self.loadViewSource()
        XCTAssertTrue(
            source.contains(#"Text("Transaction Classification")"#),
            "Classification section must use Transaction Classification heading."
        )
    }

    func testCandidatesAndEmailPaneScenarioVerifiesPaneHeadings() throws {
        // #R066-T01 #R067-T01
        let source = try Self.loadUITestSource()
        XCTAssertTrue(
            source.contains(#"app.staticTexts["Transaction - Email Match Candidates"].exists"#),
            "Smoke suite must verify Transaction - Email Match Candidates heading."
        )
        XCTAssertTrue(
            source.contains(#"app.staticTexts["Transaction Classification"].exists"#),
            "Smoke suite must verify Transaction Classification heading."
        )
    }
}

private extension MatchAndClassifyViewsRequirementsTests {
    static func loadViewSource() throws -> String {
        let currentFile = URL(fileURLWithPath: #filePath)
        let packageRoot = currentFile
            .deletingLastPathComponent() // TransactionClassifierTests
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // macos-ui package root
        let viewFile = packageRoot
            .appendingPathComponent("Sources")
            .appendingPathComponent("TransactionClassifier")
            .appendingPathComponent("MatchAndClassifyViews.swift")
        return try String(contentsOf: viewFile, encoding: .utf8)
    }

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
