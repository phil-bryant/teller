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

    func testFilterToolbarUsesTwoRows() throws {
        // #R005-T02
        let source = try Self.loadViewSource()
        XCTAssertTrue(
            source.contains("MatchAndClassifyToolbar"),
            "Filter toolbar must remain a dedicated view."
        )
        let toolbarStart = try XCTUnwrap(source.range(of: "private struct MatchAndClassifyToolbar"))
        let toolbarEnd = try XCTUnwrap(source.range(of: "private struct MatchAndClassifyTransactionsPane")).lowerBound
        let toolbarSource = String(source[toolbarStart.lowerBound..<toolbarEnd])
        XCTAssertTrue(
            toolbarSource.contains("VStack(alignment: .leading, spacing: 6)"),
            "Filter toolbar must use a two-row VStack layout."
        )
        XCTAssertTrue(
            toolbarSource.components(separatedBy: "HStack(spacing: 8)").count >= 4,
            "Filter toolbar must render controls on three HStack rows."
        )
        XCTAssertFalse(
            toolbarSource.contains(#"Button("Refresh")"#),
            "Refresh must not live in the global filter toolbar."
        )
        XCTAssertFalse(
            toolbarSource.contains(#"Button("Load more")"#),
            "Load more must not live in the global filter toolbar."
        )
    }

    func testTransactionPaneExposesRefreshAndLoadMoreActions() throws {
        // #R068-T01
        let source = try Self.loadViewSource()
        let paneStart = try XCTUnwrap(source.range(of: "private struct MatchAndClassifyTransactionsPane"))
        let paneEnd = try XCTUnwrap(source.range(of: "/// Each transaction row in the unified Match & Classify left pane")).lowerBound
        let paneSource = String(source[paneStart.lowerBound..<paneEnd])
        XCTAssertTrue(
            paneSource.contains(#"Text("Transactions")"#),
            "Transactions pane must keep its heading."
        )
        XCTAssertTrue(
            paneSource.contains(#"Button("Refresh") { Task { await viewModel.loadAll() } }"#),
            "Transactions pane must expose Refresh beside the list."
        )
        XCTAssertTrue(
            paneSource.contains(#"Button("Load more") { Task { await viewModel.loadMore() } }"#),
            "Transactions pane must expose Load more beside the list."
        )
        XCTAssertTrue(
            paneSource.contains(#".accessibilityIdentifier("refresh-button")"#),
            "Transactions pane Refresh must keep refresh-button identifier."
        )
        XCTAssertTrue(
            paneSource.contains(#".accessibilityIdentifier("load-more-button")"#),
            "Transactions pane Load more must keep load-more-button identifier."
        )
    }

    func testRefreshAndLoadMoreScenariosUseTransactionPaneControls() throws {
        // #R068-T02
        let source = try Self.loadUITestSource()
        XCTAssertTrue(
            source.contains("runRefreshButtonScenario"),
            "Smoke suite must include Refresh button scenario."
        )
        XCTAssertTrue(
            source.contains("runLoadMoreButtonScenario"),
            "Smoke suite must include Load more button scenario."
        )
        XCTAssertTrue(
            source.contains(#"uiElement("refresh-button").click()"#),
            "Refresh scenario must click refresh-button."
        )
        XCTAssertTrue(
            source.contains(#"uiElement("load-more-button")"#),
            "Load more scenario must target load-more-button."
        )
    }

    func testAdvancedTransactionFilterControlsExposeAccessibilityIdentifiers() throws {
        // #R070-T01
        let source = try Self.loadViewSource()
        let toolbarStart = try XCTUnwrap(source.range(of: "private struct MatchAndClassifyToolbar"))
        let toolbarEnd = try XCTUnwrap(source.range(of: "private struct MatchAndClassifyTransactionsPane")).lowerBound
        let toolbarSource = String(source[toolbarStart.lowerBound..<toolbarEnd])
        for identifier in [
            "transaction-start-date-field",
            "transaction-end-date-field",
            "transaction-institution-picker",
            "transaction-min-amount-field",
            "transaction-max-amount-field",
        ] {
            XCTAssertTrue(
                toolbarSource.contains("accessibilityIdentifier(\"\(identifier)\")"),
                "Advanced transaction filter toolbar must expose \(identifier)."
            )
        }
    }

    func testAdvancedEmailSearchFieldsExposeAccessibilityIdentifiers() throws {
        // #R071-T01
        let source = try Self.loadViewSource()
        for identifier in [
            "mailcart-search-subject-field",
            "mailcart-search-sender-field",
            "mailcart-search-body-field",
            "mailcart-search-start-date-field",
            "mailcart-search-end-date-field",
        ] {
            XCTAssertTrue(
                source.contains("accessibilityIdentifier(\"\(identifier)\")"),
                "Advanced email search must expose \(identifier)."
            )
        }
    }

    func testAdvancedFilterScenariosAreInSmokeSuite() throws {
        // #R070-T02 #R071-T02 #R090-T02
        let source = try Self.loadUITestSource()
        XCTAssertTrue(source.contains("runAdvancedTransactionFilterScenario"))
        XCTAssertTrue(source.contains("runAdvancedEmailSearchScenario"))
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
