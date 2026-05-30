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

    func testEmailSectionExposesBodyModePickerAndRawRenderedIdentifiers() throws {
        // #R075-T01
        let source = try Self.loadViewSource()
        XCTAssertTrue(
            source.contains(#".accessibilityIdentifier("email-body-mode-picker")"#),
            "Email section must expose a body mode picker identifier."
        )
        XCTAssertTrue(
            source.contains(#".accessibilityIdentifier("email-body-mode-rendered")"#),
            "Rendered segment must expose a stable identifier."
        )
        XCTAssertTrue(
            source.contains(#".accessibilityIdentifier("email-body-mode-raw")"#),
            "Raw segment must expose a stable identifier."
        )
        XCTAssertTrue(
            source.contains(#".onChange(of: viewModel.selectedEmail?.email_message_id)"#),
            "Body mode must reset when selected email changes."
        )
        XCTAssertTrue(
            source.contains(#".accessibilityIdentifier("email-body-raw-text")"#),
            "Raw mode must expose text-first raw body identifier."
        )
        XCTAssertTrue(
            source.contains(#".accessibilityIdentifier("email-body-raw-html")"#),
            "Raw mode must expose html-source fallback identifier."
        )
    }

    func testCandidatesAndEmailPaneScenarioCoversRawModeAndReset() throws {
        // #R075-T01
        let source = try Self.loadUITestSource()
        XCTAssertTrue(
            source.contains(#"uiElement("email-body-mode-raw").click()"#),
            "Smoke scenario must toggle the body mode to Raw."
        )
        XCTAssertTrue(
            source.contains(#"waitForElement(uiElement("email-body-raw-text"), timeout: waitTimeout * 3)"#),
            "Smoke scenario must verify raw mode text-first output."
        )
        XCTAssertTrue(
            source.contains(#"waitForElement(uiElement("email-body-html"), timeout: waitTimeout * 3)"#),
            "Smoke scenario must verify rendered html is visible after selecting another email."
        )
    }

    func testTransactionsPaneOwnsTransactionFilterControls() throws {
        // #R005-T02 #R005-T03 #R005-T04
        let source = try Self.loadViewSource()
        assertNoSharedToolbar(in: source)
        let paneSource = try transactionsPaneSource(from: source)
        assertTransactionsPaneContainsFilterControls(in: paneSource)
        try assertTransactionsPaneFilterControlOrdering(in: paneSource)
        assertTransactionsPaneUsesSharedFieldWidths(in: paneSource)
    }

    func testCandidatesPaneOwnsMatchControls() throws {
        // #R072-T01
        let source = try Self.loadViewSource()
        let candidatesStart = try XCTUnwrap(source.range(of: "private struct CandidatesPane"))
        let candidatesEnd = try XCTUnwrap(source.range(of: "private struct CandidateRowView")).lowerBound
        let candidatesSource = String(source[candidatesStart.lowerBound..<candidatesEnd])
        XCTAssertTrue(
            candidatesSource.contains(#".accessibilityIdentifier("match-review-state-picker")"#),
            "Candidates pane must own the match state picker."
        )
        XCTAssertTrue(
            candidatesSource.contains(#".accessibilityIdentifier("match-review-only-unmoved-toggle")"#),
            "Candidates pane must own the only-unmoved toggle."
        )

        let transactionsStart = try XCTUnwrap(source.range(of: "private struct MatchAndClassifyTransactionsPane"))
        let transactionsEnd = try XCTUnwrap(source.range(of: "/// Each transaction row in the unified Match & Classify left pane")).lowerBound
        let transactionsSource = String(source[transactionsStart.lowerBound..<transactionsEnd])
        XCTAssertFalse(
            transactionsSource.contains("match-review-state-picker"),
            "Transactions pane must not host match-state controls."
        )
        XCTAssertFalse(
            transactionsSource.contains("match-review-only-unmoved-toggle"),
            "Transactions pane must not host only-unmoved controls."
        )
    }

    func testTransactionPaneExposesRefreshAndLoadMoreActions() throws {
        // #R068-T01 #R068-T03
        let source = try Self.loadViewSource()
        let paneStart = try XCTUnwrap(source.range(of: "private struct MatchAndClassifyTransactionsPane"))
        let paneEnd = try XCTUnwrap(source.range(of: "/// Each transaction row in the unified Match & Classify left pane")).lowerBound
        let paneSource = String(source[paneStart.lowerBound..<paneEnd])
        XCTAssertTrue(
            paneSource.contains(#"Text("Transactions")"#),
            "Transactions pane must keep its heading."
        )
        XCTAssertTrue(
            paneSource.contains(#"Button("Next Unclassified") { viewModel.nextUnclassified() }"#),
            "Transactions pane must expose Next Unclassified beside list actions."
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
            paneSource.contains(#".accessibilityIdentifier("next-unclassified-button")"#),
            "Transactions pane Next Unclassified must keep next-unclassified-button identifier."
        )
        XCTAssertTrue(
            paneSource.contains(#".accessibilityIdentifier("load-more-button")"#),
            "Transactions pane Load more must keep load-more-button identifier."
        )
        let nextIndex = try XCTUnwrap(paneSource.range(of: #".accessibilityIdentifier("next-unclassified-button")"#)?.lowerBound)
        let refreshIndex = try XCTUnwrap(paneSource.range(of: #".accessibilityIdentifier("refresh-button")"#)?.lowerBound)
        XCTAssertLessThan(
            nextIndex,
            refreshIndex,
            "Next Unclassified must be declared to the left of Refresh in transactions actions row."
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
        let paneStart = try XCTUnwrap(source.range(of: "private struct MatchAndClassifyTransactionsPane"))
        let paneEnd = try XCTUnwrap(source.range(of: "/// Each transaction row in the unified Match & Classify left pane")).lowerBound
        let paneSource = String(source[paneStart.lowerBound..<paneEnd])
        for identifier in [
            "transaction-start-date-field",
            "transaction-end-date-field",
            "transaction-institution-picker",
            "transaction-min-amount-field",
            "transaction-max-amount-field",
        ] {
            XCTAssertTrue(
                paneSource.contains("accessibilityIdentifier(\"\(identifier)\")"),
                "Advanced transaction filters in Transactions pane must expose \(identifier)."
            )
        }
    }

    func testClassificationControlsLiveInClassifySection() throws {
        // #R015-T02 #R015-T03
        let source = try Self.loadViewSource()
        let classifyStart = try XCTUnwrap(source.range(of: "private struct ClassifySection"))
        let classifyEnd = try XCTUnwrap(source.range(of: "private struct EmailSection")).lowerBound
        let classifySource = String(source[classifyStart.lowerBound..<classifyEnd])
        XCTAssertTrue(
            classifySource.contains("CategoryTypeaheadField"),
            "ClassifySection must host the category typeahead."
        )
        XCTAssertTrue(
            classifySource.contains(#".accessibilityIdentifier("apply-selected-button")"#),
            "ClassifySection must host Apply to Selected."
        )
        XCTAssertTrue(
            classifySource.contains(#".accessibilityIdentifier("clear-selection-button")"#),
            "ClassifySection must host Clear."
        )
        XCTAssertTrue(
            classifySource.contains(#".accessibilityIdentifier("undo-button")"#),
            "ClassifySection must host Undo."
        )
        let clearIndex = try XCTUnwrap(classifySource.range(of: #".accessibilityIdentifier("clear-selection-button")"#)?.lowerBound)
        let undoIndex = try XCTUnwrap(classifySource.range(of: #".accessibilityIdentifier("undo-button")"#)?.lowerBound)
        XCTAssertLessThan(
            clearIndex,
            undoIndex,
            "Undo must be declared to the right of Clear in classification actions row."
        )
    }

    func testAdvancedEmailSearchFieldsExposeAccessibilityIdentifiers() throws {
        // #R071-T01 #R071-T08
        let source = try Self.loadViewSource()
        for identifier in [
            "mailcart-search-subject-field",
            "mailcart-search-body-field",
            "mailcart-search-sender-field",
            "mailcart-search-start-date-field",
            "mailcart-search-end-date-field",
        ] {
            XCTAssertTrue(
                source.contains("accessibilityIdentifier(\"\(identifier)\")"),
                "Advanced email search must expose \(identifier)."
            )
        }
        XCTAssertTrue(
            source.contains(#"TextField("Start date", text: $viewModel.mailcartSearchStartDate)"#),
            "Search Email section must label received-start as Start date."
        )
        XCTAssertTrue(
            source.contains(#"TextField("End date", text: $viewModel.mailcartSearchEndDate)"#),
            "Search Email section must label received-end as End date."
        )
        try assertSearchEmailFieldTabOrder(in: source)
    }

    func testAdvancedEmailSearchShowsScopedAndInclusiveContractHint() throws {
        // #R071-T06
        let source = try Self.loadViewSource()
        XCTAssertTrue(
            source.contains(#".accessibilityIdentifier("mailcart-search-contract-hint")"#),
            "Search Email section must expose a stable contract hint identifier."
        )
        XCTAssertTrue(
            source.contains("Dates are inclusive"),
            "Search Email hint must clarify date bound inclusivity."
        )
        XCTAssertTrue(
            source.contains("combined with AND"),
            "Search Email hint must clarify multi-field AND behavior."
        )
    }

    func testAdvancedFilterScenariosAreInSmokeSuite() throws {
        // #R070-T02 #R071-T02 #R090-T02
        let source = try Self.loadUITestSource()
        XCTAssertTrue(source.contains("runAdvancedTransactionFilterScenario"))
        XCTAssertTrue(source.contains("runAdvancedEmailSearchScenario"))
    }

    func testAdvancedTransactionFilterScenarioExercisesEachScalarControl() throws {
        // #R070-T03
        let source = try Self.loadUITestSource()
        XCTAssertTrue(source.contains(#"replaceText(in: uiElement("transaction-start-date-field"), with: "2026-04-20")"#))
        XCTAssertTrue(source.contains(#"replaceText(in: uiElement("transaction-end-date-field"), with: "2026-04-19")"#))
        XCTAssertTrue(source.contains(#"replaceText(in: uiElement("transaction-min-amount-field"), with: "50")"#))
        XCTAssertTrue(source.contains(#"replaceText(in: uiElement("transaction-max-amount-field"), with: "20")"#))
    }

    func testAdvancedEmailSearchScenarioExercisesSenderBodyAndDateFilters() throws {
        // #R071-T03 #R071-T04 #R071-T05 #R071-T09
        let source = try Self.loadUITestSource()
        XCTAssertTrue(source.contains(#"pasteText("alerts@transit.example.com", into: uiElement("mailcart-search-sender-field"))"#))
        XCTAssertTrue(source.contains(#"pasteText("nobody@nope.example.com", into: uiElement("mailcart-search-sender-field"))"#))
        XCTAssertTrue(source.contains(#"!uiElement("mailcart-hit-row-msg_search_001").exists"#))
        XCTAssertTrue(source.contains(#"!uiElement("mailcart-hit-row-msg_search_002").exists"#))
        XCTAssertTrue(source.contains(#"pasteText("Charge posted", into: uiElement("mailcart-search-body-field"))"#))
        XCTAssertTrue(source.contains(#"replaceText(in: uiElement("mailcart-search-start-date-field"), with: "2026-04-19")"#))
        XCTAssertTrue(source.contains(#"replaceText(in: uiElement("mailcart-search-end-date-field"), with: "2026-04-18")"#))
        XCTAssertTrue(source.contains(#"app.typeKey(.tab, modifierFlags: [])"#))
        XCTAssertTrue(source.contains(#"app.typeText("body-tab-probe")"#))
        XCTAssertTrue(source.contains(#"app.typeText("sender-tab-probe")"#))
        XCTAssertTrue(source.contains(#"Tab from Sender should route typing to Start date."#))
    }

    func testAdvancedEmailSearchScenarioPersistsHitsAcrossTransactionSelection() throws {
        // #R071-T07
        let source = try Self.loadUITestSource()
        XCTAssertTrue(
            source.contains(#"selectTransactionRow("txn_001", label: "Coffee Roasters")"#),
            "Advanced email search smoke scenario must switch transactions after search criteria are applied."
        )
        XCTAssertTrue(
            source.contains(#"waitForElement(uiElement("mailcart-hit-row-msg_search_001"), timeout: waitTimeout * 3)"#),
            "Advanced email search smoke scenario must retain hit rows after switching transactions."
        )
    }

    func testMatchActionsBarUsesCompactButtonLabelsInOrder() throws {
        // #R045-T02
        let source = try Self.loadViewSource()
        let barStart = try XCTUnwrap(source.range(of: "private struct MatchActionsBar"))
        let barEnd = try XCTUnwrap(source.range(of: "private final class NonFocusStealingWebView")).lowerBound
        let barSource = String(source[barStart.lowerBound..<barEnd])
        for label in ["Confirm", "Override", "No-email", "Clear"] {
            XCTAssertTrue(
                barSource.contains(#"Button("\#(label)")"#),
                "Match action bar must expose a \(label) button."
            )
        }
        let confirmIndex = try lowerBound(of: #".accessibilityIdentifier("match-confirm-button")"#, in: barSource)
        let overrideIndex = try lowerBound(of: #".accessibilityIdentifier("match-override-button")"#, in: barSource)
        let noEmailIndex = try lowerBound(of: #".accessibilityIdentifier("match-no-email-button")"#, in: barSource)
        let clearIndex = try lowerBound(of: #".accessibilityIdentifier("match-clear-button")"#, in: barSource)
        XCTAssertLessThan(confirmIndex, overrideIndex, "Confirm must precede Override.")
        XCTAssertLessThan(overrideIndex, noEmailIndex, "Override must precede No-email.")
        XCTAssertLessThan(noEmailIndex, clearIndex, "No-email must precede Clear.")
    }

    func testClassifySectionOmitsRedundantTransactionHeader() throws {
        // #R030-T01
        let source = try Self.loadViewSource()
        XCTAssertFalse(
            source.contains("selected-transaction-header"),
            "ClassifySection must not render a redundant transaction id beside classification actions."
        )
        XCTAssertTrue(
            source.contains(#".accessibilityIdentifier("selection-count")"#),
            "ClassifySection must keep selection-count visible."
        )
    }

    func testEmailBodyWebViewNavigationDelegateCancelsInPlaceNavigationAndOpensExternalLinks() throws {
        // #R079-T01
        let source = try Self.loadViewSource()
        XCTAssertTrue(
            source.contains("decidePolicyFor navigationAction: WKNavigationAction"),
            "Email web view coordinator must implement a navigation policy delegate."
        )
        XCTAssertTrue(
            source.contains("NSWorkspace.shared.open(url)"),
            "Email web view delegate must open clicked links externally."
        )
        XCTAssertTrue(
            source.contains("decisionHandler(.cancel)"),
            "Email web view delegate must cancel in-webview navigation."
        )
    }

    func testRenderedEmailPathUsesWrappedSanitizedHTMLWithCSP() throws {
        // #R078-T01
        let source = try Self.loadViewSource()
        XCTAssertTrue(
            source.contains("nsView.loadHTMLString(wrappedEmailHTML(htmlBody), baseURL: nil)"),
            "Rendered email path must route through wrapped sanitized HTML renderer."
        )
        XCTAssertTrue(
            source.contains("#R078: Rendered HTML path sanitizes and wraps content with restrictive CSP."),
            "Rendered email path must keep explicit R078 sanitization/CSP traceability."
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

private extension MatchAndClassifyViewsRequirementsTests {
    func assertNoSharedToolbar(in source: String) {
        XCTAssertFalse(
            source.contains("private struct MatchAndClassifyToolbar"),
            "Transaction and match controls must not be grouped into a shared toolbar."
        )
        XCTAssertFalse(
            source.contains("MatchAndClassifyToolbar(viewModel: viewModel)"),
            "Main content must not render a shared toolbar above panes."
        )
    }

    func transactionsPaneSource(from source: String) throws -> String {
        let paneStart = try XCTUnwrap(source.range(of: "private struct MatchAndClassifyTransactionsPane"))
        let paneEnd = try XCTUnwrap(source.range(of: "/// Each transaction row in the unified Match & Classify left pane")).lowerBound
        return String(source[paneStart.lowerBound..<paneEnd])
    }

    func assertTransactionsPaneContainsFilterControls(in paneSource: String) {
        XCTAssertTrue(
            paneSource.contains("WrappingControlRow"),
            "Transactions pane controls should use responsive wrapping rows."
        )
        XCTAssertTrue(
            paneSource.contains(#".accessibilityIdentifier("search-field")"#),
            "Transactions pane must own the search field."
        )
        XCTAssertTrue(
            paneSource.contains(#".accessibilityIdentifier("only-unclassified-toggle")"#),
            "Transactions pane must own the unclassified toggle."
        )
        for identifier in [
            "transaction-start-date-field",
            "transaction-end-date-field",
            "transaction-institution-picker",
            "transaction-min-amount-field",
            "transaction-max-amount-field",
        ] {
            XCTAssertTrue(
                paneSource.contains("accessibilityIdentifier(\"\(identifier)\")"),
                "Transactions pane must expose \(identifier)."
            )
        }
        XCTAssertTrue(
            paneSource.contains(#"Picker("", selection: $viewModel.transactionInstitutionId)"#),
            "Institution picker must hide its visible label text."
        )
        XCTAssertTrue(
            paneSource.contains(".labelsHidden()"),
            "Institution picker should use labelsHidden to keep row 2 compact."
        )
    }

    func assertTransactionsPaneFilterControlOrdering(in paneSource: String) throws {
        let institutionIdentifier = #".accessibilityIdentifier("transaction-institution-picker")"#
        let minAmountIdentifier = #".accessibilityIdentifier("transaction-min-amount-field")"#
        let maxAmountIdentifier = #".accessibilityIdentifier("transaction-max-amount-field")"#
        let searchIdentifier = #".accessibilityIdentifier("search-field")"#
        let startDateIdentifier = #".accessibilityIdentifier("transaction-start-date-field")"#
        let endDateIdentifier = #".accessibilityIdentifier("transaction-end-date-field")"#
        let unclassifiedIdentifier = #".accessibilityIdentifier("only-unclassified-toggle")"#

        let searchIndex = try lowerBound(of: searchIdentifier, in: paneSource)
        let startDateIndex = try lowerBound(of: startDateIdentifier, in: paneSource)
        let endDateIndex = try lowerBound(of: endDateIdentifier, in: paneSource)
        let institutionIndex = try lowerBound(of: institutionIdentifier, in: paneSource)
        let minAmountIndex = try lowerBound(of: minAmountIdentifier, in: paneSource)
        let maxAmountIndex = try lowerBound(of: maxAmountIdentifier, in: paneSource)
        let unclassifiedIndex = try lowerBound(of: unclassifiedIdentifier, in: paneSource)

        XCTAssertLessThan(
            searchIndex,
            startDateIndex,
            "Transactions pane must place search on the first row above date+amount controls."
        )
        XCTAssertLessThan(
            minAmountIndex,
            institutionIndex,
            "Transactions pane row 2 must place Institution after Min amount."
        )
        XCTAssertLessThan(
            institutionIndex,
            endDateIndex,
            "Transactions pane must keep row 3 controls below row 2."
        )
        XCTAssertLessThan(
            endDateIndex,
            maxAmountIndex,
            "Transactions pane row 3 must place Max amount after End date."
        )
        XCTAssertLessThan(
            maxAmountIndex,
            unclassifiedIndex,
            "Transactions pane must keep Unclassified toggle on a row below amount controls."
        )
        XCTAssertGreaterThanOrEqual(
            paneSource.components(separatedBy: "WrappingControlRow").count - 1,
            3,
            "Transactions pane should define responsive wrapping rows for filters and actions."
        )
    }

    func assertTransactionsPaneUsesSharedFieldWidths(in paneSource: String) {
        XCTAssertTrue(
            paneSource.contains("let dateFieldWidth: CGFloat ="),
            "Transactions pane must define a shared width token for Start/End date fields."
        )
        XCTAssertTrue(
            paneSource.contains("let amountFieldWidth: CGFloat ="),
            "Transactions pane must define a shared width token for Min/Max amount fields."
        )
        XCTAssertGreaterThanOrEqual(
            paneSource.components(separatedBy: ".frame(width: dateFieldWidth)").count - 1,
            2,
            "Start date and End date must both use dateFieldWidth."
        )
        XCTAssertGreaterThanOrEqual(
            paneSource.components(separatedBy: ".frame(width: amountFieldWidth)").count - 1,
            2,
            "Min amount and Max amount must both use amountFieldWidth."
        )
    }

    func lowerBound(of needle: String, in source: String) throws -> String.Index {
        try XCTUnwrap(source.range(of: needle)?.lowerBound, "Expected snippet in transactions pane: \(needle)")
    }

    func assertSearchEmailFieldTabOrder(in source: String) throws {
        let subjectIdentifier = #".accessibilityIdentifier("mailcart-search-subject-field")"#
        let bodyIdentifier = #".accessibilityIdentifier("mailcart-search-body-field")"#
        let senderIdentifier = #".accessibilityIdentifier("mailcart-search-sender-field")"#
        let startDateIdentifier = #".accessibilityIdentifier("mailcart-search-start-date-field")"#
        let endDateIdentifier = #".accessibilityIdentifier("mailcart-search-end-date-field")"#

        let subjectIndex = try lowerBound(of: subjectIdentifier, in: source)
        let bodyIndex = try lowerBound(of: bodyIdentifier, in: source)
        let senderIndex = try lowerBound(of: senderIdentifier, in: source)
        let startDateIndex = try lowerBound(of: startDateIdentifier, in: source)
        let endDateIndex = try lowerBound(of: endDateIdentifier, in: source)

        XCTAssertLessThan(subjectIndex, bodyIndex, "Search Email Tab order must move Subject -> Body keyword.")
        XCTAssertLessThan(bodyIndex, senderIndex, "Search Email Tab order must move Body keyword -> Sender.")
        XCTAssertLessThan(senderIndex, startDateIndex, "Search Email Tab order must move Sender -> Start date.")
        XCTAssertLessThan(startDateIndex, endDateIndex, "Search Email Tab order must move Start date -> End date.")
    }
}
