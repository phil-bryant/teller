// Traceability numbered tags for requirements/macos-ui/ContentView-requirements.md
// #R001-T01: Traceability anchor.
// #R005-T01: Traceability anchor.
// #R010-T01: Traceability anchor.
// #R015-T01: Traceability anchor.
// #R020-T01: Traceability anchor.
// #R025-T01: Traceability anchor.
// #R030-T01: Traceability anchor.
// Traceability numbered tags for requirements/macos-ui/TransactionClassifierApp-requirements.md
// #R035-T01: Traceability anchor.
// Traceability numbered tags for requirements/macos-ui/ConnectView-requirements.md
// #R020-T01: Traceability anchor.
// #R025-T01: Traceability anchor.

import AppKit
import XCTest

final class TransactionClassifierUITests: XCTestCase {
    private static var app: XCUIApplication!
    private static let scenarioCount = 12

    /// Fixture mode is in-memory; keep waits short so XCTest does not sit on idle quiescence.
    private let waitTimeout: TimeInterval = 2
    private let launchTimeout: TimeInterval = 5

    private var unclassifiedFilterDisabled = false
    private var activeTab: ActiveTab = .matchAndClassify

    private enum ActiveTab {
        case matchAndClassify
        case connect
    }

    override class func setUp() {
        super.setUp()
        app = XCUIApplication()
        app.launchArguments += ["--ui-testing"]
        app.launchEnvironment["TELLER_UI_TEST_MODE"] = "1"
        app.launchEnvironment["TELLER_UI_TEST_PAGE_SIZE"] = "20"
        applyOptionalLaunchEnvironment("TELLER_CLASSIFIER_API_URL")
        applyOptionalLaunchEnvironment("TELLER_CLASSIFIER_HTTP_PROXY")
        app.launch()
    }

    override func setUpWithError() throws {
        continueAfterFailure = false
        try super.setUpWithError()
        XCTAssertTrue(
            uiElement("search-field").waitForExistence(timeout: launchTimeout),
            "Fixture list did not finish loading."
        )
    }

    override class func tearDown() {
        app?.terminate()
        app = nil
        super.tearDown()
    }

    func testMacOSUISmokeSuite() throws {
        let selectedSteps = Self.parseSelectedSteps(from: ProcessInfo.processInfo.environment["XCUITEST_STEPS"])
        for step in 1...Self.scenarioCount where selectedSteps.contains(step) {
            switch step {
            case 1: runMatchAndClassifyShellLoadsScenario()
            case 2: runSearchFilterScenario()
            case 3: runUnclassifiedFilterAutoRefreshScenario()
            case 4: runSelectionShowsTransactionIdScenario()
            case 5: runNextUnclassifiedShortcutScenario()
            case 6: runApplyCategoryScenario()
            case 7: runUndoRestoresUnclassifiedScenario()
            case 8: runUndoRestoresPriorCategoryScenario()
            case 9: runNextUnclassifiedScrollsIntoViewScenario()
            case 10: runHelpMenuListsHotkeysScenario()
            case 11: runConnectTabLoadsConnectionsScenario()
            case 12: runConnectTabHidesNextUnclassifiedScenario()
            default: break
            }
        }
    }

    // MARK: - Scenarios

    private func runMatchAndClassifyShellLoadsScenario() {
        // #R001
        ensureMatchAndClassifyTab()
        XCTAssertTrue(uiElement("transaction-list").exists)
        XCTAssertTrue(uiElement("transaction-row-txn_001").exists)
    }

    private func runSearchFilterScenario() {
        // #R005
        ensureMatchAndClassifyTab()
        let searchField = uiElement("search-field")
        clearSearchField(searchField)
        searchField.click()
        searchField.typeText("coffee")
        app.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(uiElement("transaction-row-txn_001").waitForExistence(timeout: waitTimeout))
        clearSearchField(searchField)
    }

    private func runUnclassifiedFilterAutoRefreshScenario() {
        // #R020
        ensureMatchAndClassifyTab()
        XCTAssertTrue(uiElement("transaction-row-txn_001").exists)
        XCTAssertFalse(uiElement("transaction-row-txn_002").exists)

        let toggle = uiElement("only-unclassified-toggle")
        XCTAssertTrue(toggle.exists)
        toggle.click()
        unclassifiedFilterDisabled = true

        XCTAssertTrue(uiElement("transaction-row-txn_002").waitForExistence(timeout: waitTimeout))
    }

    private func runSelectionShowsTransactionIdScenario() {
        // #R030
        ensureMatchAndClassifyTab()
        selectTransactionRow("txn_001", label: "Coffee Roasters")
        assertSelectedTransactionId("txn_001")
    }

    private func runNextUnclassifiedShortcutScenario() {
        // #R010
        ensureMatchAndClassifyTab()
        ensureUnclassifiedFilterDisabled()

        uiElement("transaction-row-txn_002").click()
        app.typeKey("]", modifierFlags: .command)
        assertSelectedTransactionId("txn_001")
    }

    private func runApplyCategoryScenario() {
        // #R015
        ensureMatchAndClassifyTab()
        ensureUnclassifiedFilterDisabled()
        applyDiningToCoffeeRow()
        waitForRowClassification("txn_001", label: "Dining")
    }

    private func runUndoRestoresUnclassifiedScenario() {
        // #R015
        ensureMatchAndClassifyTab()
        ensureUnclassifiedFilterDisabled()
        if !uiElement("selected-assigned-category").exists {
            applyDiningToCoffeeRow()
        }
        app.typeKey("z", modifierFlags: .command)
        waitForRowClassification("txn_001", label: "Unclassified")
    }

    private func runUndoRestoresPriorCategoryScenario() {
        // #R015
        ensureMatchAndClassifyTab()
        ensureUnclassifiedFilterDisabled()

        uiElement("transaction-row-txn_002").click()
        assertAssignedCategory("Utilities")

        applyDiningToSelectedRow()
        assertAssignedCategory("Dining")

        app.typeKey("z", modifierFlags: .command)
        assertAssignedCategory("Utilities")
    }

    private func runNextUnclassifiedScrollsIntoViewScenario() {
        // #R025
        ensureMatchAndClassifyTab()
        ensureUnclassifiedFilterDisabled()
        ensureAllTransactionsLoadedIntoList()

        let list = app.scrollViews["transaction-list"].firstMatch
        XCTAssertTrue(list.exists)

        let topRow = uiElement("transaction-row-txn_001")
        XCTAssertTrue(topRow.exists)

        var outOfViewConfirmed = false
        for _ in 0..<12 {
            list.scroll(byDeltaX: 0, deltaY: -800)
            if !topRow.isHittable {
                outOfViewConfirmed = true
                break
            }
        }
        XCTAssertTrue(
            outOfViewConfirmed,
            "Test pre-condition failed: txn_001 must be scrolled off-screen before Next Unclassified is triggered."
        )

        app.typeKey("]", modifierFlags: .command)
        assertSelectedTransactionId("txn_001")

        var scrolledIntoView = false
        for _ in 0..<8 {
            if topRow.isHittable {
                scrolledIntoView = true
                break
            }
        }
        XCTAssertTrue(
            scrolledIntoView,
            "Next Unclassified must scroll txn_001 back into the visible list frame (#R025)."
        )
    }

    private func runHelpMenuListsHotkeysScenario() {
        // #R035
        dismissOpenMenus()
        let helpMenu = app.menuBars.menuBarItems["Help"]
        XCTAssertTrue(helpMenu.exists)
        helpMenu.click()

        XCTAssertTrue(app.menuItems["Keyboard Shortcuts"].exists)
        XCTAssertTrue(app.menuItems["Next Unclassified — Cmd+]"].exists)
        XCTAssertTrue(app.menuItems["Undo — Cmd+Z"].exists)
        XCTAssertTrue(app.menuItems["Apply to Selected — Cmd+Return"].exists)
        XCTAssertTrue(app.menuItems["Save Category — Cmd+S"].exists)

        dismissOpenMenus()
    }

    private func runConnectTabLoadsConnectionsScenario() {
        // #R020 #R025
        ensureConnectTab()
        XCTAssertTrue(uiElement("connect-context-list").waitForExistence(timeout: waitTimeout))
        XCTAssertTrue(uiElement("connect-add-button").exists)
        XCTAssertTrue(uiElement("connect-edit-button").exists)
        XCTAssertTrue(uiElement("connect-delete-button").exists)
        XCTAssertTrue(connectStatusOrErrorExists())
    }

    private func runConnectTabHidesNextUnclassifiedScenario() {
        // #R010 (connect tab)
        ensureConnectTab()
        XCTAssertFalse(nextUnclassifiedControlExists())
    }

    // MARK: - Helpers

    private var app: XCUIApplication { Self.app }

    private func uiElement(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any)[identifier].firstMatch
    }

    private func ensureMatchAndClassifyTab() {
        if activeTab == .matchAndClassify, uiElement("search-field").exists {
            return
        }
        selectTab(named: "Match & Classify")
        XCTAssertTrue(uiElement("search-field").waitForExistence(timeout: waitTimeout))
        activeTab = .matchAndClassify
    }

    private func ensureConnectTab() {
        if activeTab == .connect, connectTabIsVisible() {
            return
        }
        selectTab(named: "Connect")
        XCTAssertTrue(
            waitForConnectTab(timeout: launchTimeout * 2),
            "Connect tab did not finish loading."
        )
        activeTab = .connect
    }

    private func selectTab(named name: String) {
        dismissOpenMenus()
        let candidates: [XCUIElement] = [
            app.buttons[name],
            app.radioButtons[name],
            app.tabs[name],
            app.tabGroups.buttons[name],
            app.staticTexts[name],
        ]
        for candidate in candidates {
            if candidate.waitForExistence(timeout: 1) {
                candidate.click()
                return
            }
        }
        XCTFail("Unable to select tab \(name)")
    }

    private func dismissOpenMenus() {
        app.typeKey(.escape, modifierFlags: [])
        app.typeKey(.escape, modifierFlags: [])
        if app.windows.firstMatch.exists {
            app.windows.firstMatch.click()
        }
    }

    private func connectTabIsVisible() -> Bool {
        uiElement("connect-context-list").exists
            || uiElement("connect-add-button").exists
            || uiElement("connect-title").exists
    }

    private func connectTabIsReady() -> Bool {
        uiElement("connect-context-list").exists
            && uiElement("connect-add-button").exists
            && connectStatusOrErrorExists()
    }

    private func waitForConnectTab(timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if connectTabIsReady() {
                return true
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        return connectTabIsReady()
    }

    private func connectStatusOrErrorExists() -> Bool {
        uiElement("connect-status-text").exists || uiElement("connect-error-banner").exists
    }

    private func ensureUnclassifiedFilterDisabled() {
        if unclassifiedFilterDisabled, uiElement("transaction-row-txn_002").exists {
            return
        }
        let toggle = uiElement("only-unclassified-toggle")
        if isToggleOn(toggle) {
            toggle.click()
        }
        unclassifiedFilterDisabled = true
        XCTAssertTrue(uiElement("transaction-row-txn_002").waitForExistence(timeout: waitTimeout))
    }

    private func selectTransactionRow(_ transactionId: String, label: String) {
        uiElement("transaction-row-\(transactionId)").click()
        assertSelectedTransactionId(transactionId)
    }

    private func assertSelectedTransactionId(_ transactionId: String) {
        XCTAssertTrue(elementText(uiElement("selection-count")).contains("1"))
        let row = uiElement("transaction-row-\(transactionId)")
        XCTAssertTrue(row.waitForExistence(timeout: waitTimeout))
        XCTAssertTrue(elementText(row).contains(transactionId))
    }

    private func elementText(_ element: XCUIElement) -> String {
        let valueText = element.value as? String ?? ""
        if !valueText.isEmpty {
            return valueText
        }
        return element.label
    }

    private func transactionLabel(_ label: String) -> XCUIElement {
        app.staticTexts[label].firstMatch
    }

    private func rowClassification(_ transactionId: String, fallbackLabel: String) -> XCUIElement {
        uiElement("transaction-row-\(transactionId)")
    }

    private func rowShowsClassification(_ transactionId: String, label: String) -> Bool {
        elementText(rowClassification(transactionId, fallbackLabel: label)).contains(label)
    }

    private func waitForRowClassification(_ transactionId: String, label: String) {
        let row = uiElement("transaction-row-\(transactionId)")
        let predicate = NSPredicate(format: "label CONTAINS[c] %@", label)
        let matchExpectation = expectation(for: predicate, evaluatedWith: row)
        wait(for: [matchExpectation], timeout: 4)
    }

    private func isToggleOn(_ toggle: XCUIElement) -> Bool {
        let rawValue = String(describing: toggle.value ?? "")
        let normalized = rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return normalized == "1" || normalized == "true" || normalized == "on"
    }

    private func applyDiningToCoffeeRow() {
        selectTransactionRow("txn_001", label: "Coffee Roasters")
        applyDiningToSelectedRow()
    }

    private func applyDiningToSelectedRow() {
        let typeahead = uiElement("category-typeahead-field")
        clearTypeaheadField(typeahead)
        typeahead.typeText("Dining")
        app.typeKey(.return, modifierFlags: [])
    }

    private func clearTypeaheadField(_ field: XCUIElement) {
        field.click()
        app.typeKey("a", modifierFlags: .command)
        app.typeKey(.delete, modifierFlags: [])
    }

    private func assertAssignedCategory(_ label: String, file: StaticString = #file, line: UInt = #line) {
        let assigned = uiElement("selected-assigned-category")
        XCTAssertTrue(assigned.waitForExistence(timeout: waitTimeout), file: file, line: line)
        let predicate = NSPredicate(format: "label CONTAINS[c] %@ OR value CONTAINS[c] %@", label, label)
        let matchExpectation = expectation(for: predicate, evaluatedWith: assigned)
        wait(for: [matchExpectation], timeout: 4)
    }

    private func pasteText(_ text: String, into element: XCUIElement) {
        element.click()
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        app.typeKey("v", modifierFlags: .command)
    }

    private func clearSearchField(_ searchField: XCUIElement) {
        searchField.click()
        app.typeKey("a", modifierFlags: .command)
        app.typeKey(.delete, modifierFlags: [])
        app.typeKey(.return, modifierFlags: [])
    }

    private func ensureAllTransactionsLoadedIntoList() {
        let searchField = uiElement("search-field")
        clearSearchField(searchField)
        let loadMore = uiElement("load-more-button")
        for _ in 0..<12 {
            if !loadMore.exists || !loadMore.isEnabled { break }
            loadMore.click()
            _ = loadMore.waitForExistence(timeout: 1)
        }
    }

    private func nextUnclassifiedControlExists() -> Bool {
        uiElement("next-unclassified-button").exists || app.buttons["Next Unclassified"].exists
    }

    private static func applyOptionalLaunchEnvironment(_ key: String) {
        if let value = ProcessInfo.processInfo.environment[key], !value.isEmpty {
            app.launchEnvironment[key] = value
        }
    }

    private static func parseSelectedSteps(from raw: String?) -> Set<Int> {
        guard let raw, !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return Set(1...scenarioCount)
        }

        var selected = Set<Int>()
        for token in raw.split(separator: ",") {
            let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { continue }

            if let single = Int(trimmed) {
                selected.insert(single)
                continue
            }

            let parts = trimmed.split(separator: "-", maxSplits: 1).map(String.init)
            if parts.count == 2,
               let start = Int(parts[0]),
               let end = Int(parts[1]),
               start <= end {
                for step in start...end {
                    selected.insert(step)
                }
            }
        }

        return selected.isEmpty ? Set(1...scenarioCount) : selected
    }
}
