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
    private static let scenarioCount = 26

    /// Maximum bounds only; condition polling exits immediately once state is ready.
    private let waitTimeout: TimeInterval = 2
    private let launchTimeout: TimeInterval = 5
    private let pollInterval: TimeInterval = 0.05

    private var unclassifiedFilterDisabled = false
    private var activeTab: ActiveTab = .matchAndClassify

    private enum ActiveTab {
        case matchAndClassify
        case manageCategories
        case connect
    }

    override class func setUp() {
        super.setUp()
        app = XCUIApplication()
        app.launchArguments += ["--ui-testing"]
        app.launchEnvironment["TELLER_UI_TEST_MODE"] = "1"
        app.launchEnvironment["TELLER_UI_TEST_PAGE_SIZE"] = "5"
        app.launchEnvironment["TELLER_UI_TEST_MATCH_FIXTURE"] = "1"
        applyOptionalLaunchEnvironment("TELLER_CLASSIFIER_API_URL")
        applyOptionalLaunchEnvironment("TELLER_CLASSIFIER_HTTP_PROXY")
        app.launch()
    }

    override func setUpWithError() throws {
        continueAfterFailure = false
        try super.setUpWithError()
        XCTAssertTrue(
            waitForElement(uiElement("search-field"), timeout: launchTimeout),
            "Fixture list did not finish loading."
        )
    }
    
    func testRecordedFlow() throws {
        
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
            case 4: runMatchStatePickerScenario()
            case 5: runOnlyUnmovedToggleScenario()
            case 6: runRefreshButtonScenario()
            case 7: runSelectionShowsTransactionIdScenario()
            case 8: runNextUnclassifiedShortcutScenario()
            case 9: runLoadMoreButtonScenario()
            case 10: runApplyCategoryScenario()
            case 11: runClearSelectionScenario()
            case 12: runUndoRestoresUnclassifiedScenario()
            case 13: runUndoRestoresPriorCategoryScenario()
            case 14: runCandidatesAndEmailPaneScenario()
            case 15: runMailcartSearchScenario()
            case 16: runMatchActionsScenario()
            case 17: runNextUnclassifiedScrollsIntoViewScenario()
            case 18: runHelpMenuListsHotkeysScenario()
            case 19: runConnectTabLoadsConnectionsScenario()
            case 20: runConnectDeleteCancelScenario()
            case 21: runConnectDeleteConfirmScenario()
            case 22: runConnectAddAndEditButtonsScenario()
            case 23: runConnectTabHidesNextUnclassifiedScenario()
            case 24: runManageCategoriesLoadAndToolbarScenario()
            case 25: runManageCategoryEditAndSaveScenario()
            case 26: runManageCategoryDeleteScenario()
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
        pasteText("coffee", into: searchField)
        app.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(waitForElement(uiElement("transaction-row-txn_001"), timeout: waitTimeout))
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

        XCTAssertTrue(waitForElement(uiElement("transaction-row-txn_002"), timeout: waitTimeout))
    }

    private func runMatchStatePickerScenario() {
        ensureMatchAndClassifyTab()
        selectMatchStateFilter("Confirmed")
        XCTAssertTrue(waitForElement(uiElement("transaction-row-txn_001"), timeout: waitTimeout))
        selectMatchStateFilter("All matches")
    }

    private func runOnlyUnmovedToggleScenario() {
        ensureMatchAndClassifyTab()
        let toggle = uiElement("match-review-only-unmoved-toggle")
        XCTAssertTrue(toggle.exists)
        let initial = isToggleOn(toggle)
        toggle.click()
        XCTAssertTrue(waitUntil(timeout: waitTimeout) { isToggleOn(toggle) != initial })
        toggle.click()
        XCTAssertTrue(waitUntil(timeout: waitTimeout) { isToggleOn(toggle) == initial })
    }

    private func runRefreshButtonScenario() {
        ensureMatchAndClassifyTab()
        uiElement("refresh-button").click()
        XCTAssertTrue(
            waitUntil(timeout: waitTimeout * 2) {
                elementText(uiElement("status-text")).contains("Loaded")
            }
        )
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

    private func runClearSelectionScenario() {
        ensureMatchAndClassifyTab()
        ensureUnclassifiedFilterDisabled()
        if rowShowsClassification("txn_001", label: "Unclassified") {
            applyDiningToCoffeeRow()
            waitForRowClassification("txn_001", label: "Dining")
        }
        uiElement("clear-selection-button").click()
        waitForRowClassification("txn_001", label: "Unclassified")
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

    private func runLoadMoreButtonScenario() {
        ensureMatchAndClassifyTab()
        let loadMore = uiElement("load-more-button")
        XCTAssertTrue(loadMore.exists)
        let before = elementText(uiElement("status-text"))
        loadMore.click()
        XCTAssertTrue(
            waitUntil(timeout: waitTimeout * 2) {
                let status = elementText(uiElement("status-text"))
                return status.contains("Loaded") && status != before
            }
        )
    }

    private func runCandidatesAndEmailPaneScenario() {
        ensureMatchAndClassifyTab()
        selectTransactionRow("txn_001", label: "Coffee Roasters")
        XCTAssertTrue(waitForElement(uiElement("candidate-row-msg_receipt_001"), timeout: waitTimeout))
        XCTAssertTrue(waitForElement(uiElement("email-subject"), timeout: waitTimeout))
        XCTAssertTrue(uiElement("email-body-text").exists || uiElement("email-body-html").exists)
        XCTAssertTrue(uiElement("candidates-list").exists)
    }

    private func runMailcartSearchScenario() {
        ensureMatchAndClassifyTab()
        let field = uiElement("mailcart-search-field")
        XCTAssertTrue(field.exists)
        clearField(field)
        pasteText("transit", into: field)
        XCTAssertTrue(waitForElement(uiElement("mailcart-hit-row-msg_search_001"), timeout: waitTimeout * 3))
        uiElement("mailcart-hit-row-msg_search_001").click()
        XCTAssertTrue(
            waitUntil(timeout: waitTimeout * 2) {
                elementText(uiElement("email-subject")).contains("Transit")
            }
        )
        clearField(field)
    }

    private func runMatchActionsScenario() {
        ensureMatchAndClassifyTab()
        selectTransactionRow("txn_001", label: "Coffee Roasters")

        let note = uiElement("override-note-field")
        pasteText("fixture override note", into: note)
        let overrideId = uiElement("override-email-message-id-field")
        pasteText("msg_override_fixture", into: overrideId)

        uiElement("match-override-button").click()
        XCTAssertTrue(waitUntil(timeout: waitTimeout * 2) { elementText(uiElement("match-review-status")).contains("Overrode") })

        uiElement("match-no-email-button").click()
        XCTAssertTrue(waitUntil(timeout: waitTimeout * 2) { elementText(uiElement("match-review-status")).contains("no-email") })

        uiElement("match-clear-button").click()
        XCTAssertTrue(waitUntil(timeout: waitTimeout * 2) { elementText(uiElement("match-review-status")).contains("Cleared match") })

        uiElement("candidate-row-msg_receipt_001").click()
        uiElement("match-confirm-button").click()
        XCTAssertTrue(waitUntil(timeout: waitTimeout * 2) { elementText(uiElement("match-review-status")).contains("Confirmed") })
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
        XCTAssertTrue(waitForElement(uiElement("connect-context-list"), timeout: waitTimeout))
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

    private func runConnectDeleteCancelScenario() {
        ensureConnectTab()
        XCTAssertTrue(app.staticTexts["inst_beta"].exists)
        uiElement("connect-delete-button").click()
        if !tapVisibleButton(named: "Cancel") {
            app.typeKey(.escape, modifierFlags: [])
        }
        XCTAssertTrue(waitForElement(app.staticTexts["inst_beta"].firstMatch, timeout: waitTimeout))
    }

    private func runConnectDeleteConfirmScenario() {
        ensureConnectTab()
        XCTAssertTrue(app.staticTexts["inst_beta"].exists)
        app.staticTexts["inst_beta"].firstMatch.click()
        uiElement("connect-delete-button").click()
        XCTAssertTrue(tapVisibleButton(named: "Delete"))
        XCTAssertTrue(
            waitUntil(timeout: waitTimeout * 2) {
                !app.staticTexts["inst_beta"].exists
            }
        )
    }

    private func runConnectAddAndEditButtonsScenario() {
        ensureConnectTab()
        let addButton = uiElement("connect-add-button")
        let editButton = uiElement("connect-edit-button")
        XCTAssertTrue(addButton.exists)
        XCTAssertTrue(editButton.exists)

        // Exercise Add and Edit without entering external Teller flow.
        addButton.click()
        dismissPresentedSheetIfVisible()
        app.staticTexts["inst_alpha"].firstMatch.click()
        editButton.click()
        dismissPresentedSheetIfVisible()
    }

    private func runManageCategoriesLoadAndToolbarScenario() {
        ensureManageCategoriesTab()
        XCTAssertTrue(waitForElement(uiElement("category-manager-list"), timeout: waitTimeout))
        app.buttons["Refresh"].firstMatch.click()
        XCTAssertTrue(waitForElement(uiElement("category-status-text"), timeout: waitTimeout))
        app.buttons["New"].firstMatch.click()
        XCTAssertTrue(waitUntil(timeout: waitTimeout) {
            elementText(uiElement("category-status-text")).contains("Creating a new category")
        })
    }

    private func runManageCategoryEditAndSaveScenario() {
        ensureManageCategoriesTab()
        uiElement("category-row-101").click()

        pasteText("L1", into: uiElement("category-field-level-1"))
        pasteText("Primary", into: uiElement("category-field-level-1-name"))
        pasteText("L2", into: uiElement("category-field-level-2"))
        pasteText("Secondary", into: uiElement("category-field-level-2-name"))
        pasteText("L3", into: uiElement("category-field-level-3"))
        pasteText("L4", into: uiElement("category-field-level-4"))
        pasteText("Dining Updated", into: uiElement("category-field-categorization"))
        pasteText("General", into: uiElement("category-field-applicability"))

        uiElement("category-save-button").click()
        XCTAssertTrue(waitUntil(timeout: waitTimeout * 2) {
            elementText(uiElement("category-status-text")).contains("Saved category 101")
        })
    }

    private func runManageCategoryDeleteScenario() {
        ensureManageCategoriesTab()
        uiElement("category-row-103").click()
        uiElement("category-bulk-delete-button").click()
        XCTAssertTrue(waitUntil(timeout: waitTimeout * 2) { !uiElement("category-row-103").exists })
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
        XCTAssertTrue(waitForElement(uiElement("search-field"), timeout: waitTimeout))
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

    private func ensureManageCategoriesTab() {
        if activeTab == .manageCategories, uiElement("category-manager-list").exists {
            return
        }
        selectTab(named: "Manage Categories")
        XCTAssertTrue(waitForElement(uiElement("category-manager-list"), timeout: launchTimeout * 2))
        activeTab = .manageCategories
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
            if waitForElement(candidate, timeout: 1) {
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
        waitUntil(timeout: timeout) { connectTabIsReady() }
    }

    private func connectStatusOrErrorExists() -> Bool {
        uiElement("connect-status-text").exists || uiElement("connect-error-banner").exists
    }

    private func dismissPresentedSheetIfVisible() {
        // Escape dismisses SwiftUI sheets in our fixture mode.
        app.typeKey(.escape, modifierFlags: [])
        _ = waitUntil(timeout: waitTimeout) { app.sheets.count == 0 }
    }

    @discardableResult
    private func tapVisibleButton(named title: String) -> Bool {
        let tapped = waitUntil(timeout: waitTimeout) {
            self.visibleButton(named: title) != nil
        }
        guard tapped, let button = visibleButton(named: title) else {
            return false
        }
        button.click()
        return true
    }

    private func visibleButton(named title: String) -> XCUIElement? {
        let candidates: [XCUIElement] = [
            app.sheets.buttons[title].firstMatch,
            app.dialogs.buttons[title].firstMatch,
            app.windows.buttons[title].firstMatch,
            app.buttons[title].firstMatch,
        ]
        return candidates.first(where: { $0.exists && $0.isHittable })
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
        XCTAssertTrue(waitForElement(uiElement("transaction-row-txn_002"), timeout: waitTimeout))
    }

    private func selectTransactionRow(_ transactionId: String, label: String) {
        uiElement("transaction-row-\(transactionId)").click()
        assertSelectedTransactionId(transactionId)
    }

    private func assertSelectedTransactionId(_ transactionId: String) {
        XCTAssertTrue(elementText(uiElement("selection-count")).contains("1"))
        let row = uiElement("transaction-row-\(transactionId)")
        XCTAssertTrue(waitForElement(row, timeout: waitTimeout))
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
        XCTAssertTrue(
            waitUntil(timeout: waitTimeout * 2) {
                rowShowsClassification(transactionId, label: label)
            },
            "Timed out waiting for \(transactionId) classification to become \(label)."
        )
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
        pasteText("Dining", into: typeahead)
        app.typeKey(.return, modifierFlags: [])
    }

    private func selectMatchStateFilter(_ optionTitle: String) {
        let picker = uiElement("match-review-state-picker")
        XCTAssertTrue(waitForElement(picker, timeout: waitTimeout))
        picker.click()
        let option = app.menuItems[optionTitle].firstMatch
        XCTAssertTrue(waitForElement(option, timeout: waitTimeout))
        option.click()
    }

    private func clearTypeaheadField(_ field: XCUIElement) {
        clearField(field)
    }

    private func assertAssignedCategory(_ label: String, file: StaticString = #file, line: UInt = #line) {
        let assigned = uiElement("selected-assigned-category")
        XCTAssertTrue(waitForElement(assigned, timeout: waitTimeout), file: file, line: line)
        XCTAssertTrue(
            waitUntil(timeout: waitTimeout * 2) {
                let text = elementText(assigned).lowercased()
                return text.contains(label.lowercased())
            },
            "Timed out waiting for selected category to become \(label).",
            file: file,
            line: line
        )
    }

    private func pasteText(_ text: String, into element: XCUIElement) {
        element.click()
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        app.typeKey("v", modifierFlags: .command)
    }

    private func clearSearchField(_ searchField: XCUIElement) {
        clearField(searchField)
        app.typeKey(.return, modifierFlags: [])
    }

    private func clearField(_ field: XCUIElement) {
        field.click()
        app.typeKey("a", modifierFlags: .command)
        app.typeKey(.delete, modifierFlags: [])
    }

    private func ensureAllTransactionsLoadedIntoList() {
        let searchField = uiElement("search-field")
        clearSearchField(searchField)
        let loadMore = uiElement("load-more-button")
        for _ in 0..<12 {
            if !loadMore.exists || !loadMore.isEnabled { break }
            loadMore.click()
            _ = waitUntil(timeout: 1) { !loadMore.exists || loadMore.isEnabled }
        }
    }

    private func nextUnclassifiedControlExists() -> Bool {
        uiElement("next-unclassified-button").exists || app.buttons["Next Unclassified"].exists
    }

    @discardableResult
    private func waitForElement(_ element: XCUIElement, timeout: TimeInterval) -> Bool {
        waitUntil(timeout: timeout) { element.exists }
    }

    @discardableResult
    private func waitUntil(timeout: TimeInterval, condition: () -> Bool) -> Bool {
        if condition() {
            return true
        }

        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() {
                return true
            }
            RunLoop.current.run(until: Date().addingTimeInterval(pollInterval))
        }
        return condition()
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
