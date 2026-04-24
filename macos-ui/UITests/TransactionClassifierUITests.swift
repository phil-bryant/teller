import XCTest

final class TransactionClassifierUITests: XCTestCase {
    private var app: XCUIApplication!

    private func uiElement(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any)[identifier]
    }

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments += ["--ui-testing"]
        app.launchEnvironment["TELLER_UI_TEST_MODE"] = "1"
        app.launchEnvironment["TELLER_UI_TEST_PAGE_SIZE"] = "2"
        app.launch()
    }

    func testSearchFilterFindsFixtureRow() {
        let searchField = uiElement("search-field")
        XCTAssertTrue(searchField.waitForExistence(timeout: 5))
        searchField.click()
        searchField.typeText("coffee")
        app.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(app.staticTexts["Coffee Roasters"].waitForExistence(timeout: 5))
    }

    func testNextUnclassifiedShortcutUpdatesDetailSelection() {
        let utilityRow = app.staticTexts["Electric Utility Co"]
        XCTAssertTrue(utilityRow.waitForExistence(timeout: 5))
        utilityRow.click()

        app.typeKey("]", modifierFlags: .command)

        // In fixture mode page size is 2; from txn_002 the next unclassified is txn_001.
        XCTAssertTrue(app.staticTexts["Teller Category: food"].waitForExistence(timeout: 5))
    }

    func testApplyCategoryFromTypeaheadUpdatesSelection() {
        applyDiningToCoffeeRow()
        XCTAssertTrue(app.staticTexts["Assigned: Dining"].waitForExistence(timeout: 5))
    }

    func testUndoShortcutRestoresClassification() {
        applyDiningToCoffeeRow()
        XCTAssertTrue(app.staticTexts["Assigned: Dining"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Saved 1 classification(s)"].waitForExistence(timeout: 5))

        let undoButton = uiElement("undo-button")
        XCTAssertTrue(undoButton.waitForExistence(timeout: 5))
        undoButton.click()
        XCTAssertTrue(app.staticTexts["Assigned: none"].waitForExistence(timeout: 5))
    }

    func testLoadMoreAppendsRowsAndUpdatesStatusText() {
        let loadMoreButton = uiElement("load-more-button")
        XCTAssertTrue(loadMoreButton.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Coffee Roasters"].exists)
        XCTAssertFalse(app.staticTexts["Corner Market"].exists)

        loadMoreButton.click()

        XCTAssertTrue(app.staticTexts["Corner Market"].waitForExistence(timeout: 5))
        let statusText = uiElement("status-text")
        XCTAssertTrue(statusText.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Loaded 4 transactions (2026-04-17 to 2026-04-20)"].waitForExistence(timeout: 5))
    }

    private func applyDiningToCoffeeRow() {
        // macOS list rows can expose accessibility differently between runs; label click is more stable.
        let rowLabel = app.staticTexts["Coffee Roasters"]
        XCTAssertTrue(rowLabel.waitForExistence(timeout: 5))
        rowLabel.click()

        let typeahead = uiElement("category-typeahead-field")
        XCTAssertTrue(typeahead.waitForExistence(timeout: 5))
        typeahead.click()
        app.typeKey("a", modifierFlags: .command)
        app.typeKey(.delete, modifierFlags: [])
        typeahead.typeText("Dining")

        let option = uiElement("category-option-cat-101")
        XCTAssertTrue(option.waitForExistence(timeout: 5))
        app.typeKey(.return, modifierFlags: [])

        let applyButton = uiElement("apply-selected-button")
        XCTAssertTrue(applyButton.waitForExistence(timeout: 5))
        let enabledPredicate = NSPredicate(format: "isEnabled == true")
        let enabledExpectation = expectation(for: enabledPredicate, evaluatedWith: applyButton)
        wait(for: [enabledExpectation], timeout: 5)
        applyButton.click()
    }
}
