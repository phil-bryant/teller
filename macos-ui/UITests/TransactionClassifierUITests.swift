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
        // #R035
        app.launch()
    }

    func testSearchFilterFindsFixtureRow() {
        // #R005
        let searchField = uiElement("search-field")
        XCTAssertTrue(searchField.waitForExistence(timeout: 5))
        searchField.click()
        searchField.typeText("coffee")
        app.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(app.staticTexts["Coffee Roasters"].waitForExistence(timeout: 5))
    }

    func testNextUnclassifiedShortcutUpdatesDetailSelection() {
        // #R010
        disableUnclassifiedFilter()

        let utilityRow = app.staticTexts["Electric Utility Co"]
        XCTAssertTrue(utilityRow.waitForExistence(timeout: 5))
        utilityRow.click()

        app.typeKey("]", modifierFlags: .command)

        // In fixture mode page size is 2; from txn_002 the next unclassified is txn_001.
        XCTAssertTrue(app.staticTexts["Teller Category: food"].waitForExistence(timeout: 5))
    }

    func testApplyCategoryFromTypeaheadUpdatesSelection() {
        // #R015
        applyDiningToCoffeeRow()
        XCTAssertTrue(app.staticTexts["Assigned: Dining"].waitForExistence(timeout: 5))
    }

    func testUndoShortcutRestoresClassification() {
        // #R015
        applyDiningToCoffeeRow()
        XCTAssertTrue(app.staticTexts["Assigned: Dining"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Saved 1 classification(s)"].waitForExistence(timeout: 5))

        let undoButton = uiElement("undo-button")
        XCTAssertTrue(undoButton.waitForExistence(timeout: 5))
        undoButton.click()
        XCTAssertTrue(app.staticTexts["Assigned: none"].waitForExistence(timeout: 5))
    }

    func testUndoRestoresPriorCategoryOnAlreadyClassifiedRow() {
        // #R015
        disableUnclassifiedFilter()

        let utilityRow = app.staticTexts["Electric Utility Co"]
        XCTAssertTrue(utilityRow.waitForExistence(timeout: 5))
        utilityRow.click()

        XCTAssertTrue(app.staticTexts["Assigned: Utilities"].waitForExistence(timeout: 5))

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

        XCTAssertTrue(app.staticTexts["Assigned: Dining"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Saved 1 classification(s)"].waitForExistence(timeout: 5))

        let undoButton = uiElement("undo-button")
        XCTAssertTrue(undoButton.waitForExistence(timeout: 5))
        undoButton.click()

        // Undo must restore the prior non-nil category ("Utilities"), not just clear the row.
        XCTAssertTrue(app.staticTexts["Assigned: Utilities"].waitForExistence(timeout: 5))
    }

    func testLoadMoreAppendsRowsAndUpdatesStatusText() {
        // #R020
        disableUnclassifiedFilter()

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

    func testInitialUnclassifiedToggleIsOnByDefault() {
        // #R025
        // With the default Unclassified filter on, the first page shows only unclassified fixture rows.
        // Coffee Roasters (unclassified) must load while Electric Utility Co (classified, txn_002) must
        // be filtered out of the initial page since it is at offset 1 with pageSize=2.
        XCTAssertTrue(app.staticTexts["Coffee Roasters"].waitForExistence(timeout: 5))

        let utilityNotPresent = NSPredicate(format: "exists == false")
        let utilityExpectation = expectation(
            for: utilityNotPresent,
            evaluatedWith: app.staticTexts["Electric Utility Co"]
        )
        wait(for: [utilityExpectation], timeout: 5)

        let toggle = uiElement("only-unclassified-toggle")
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
    }

    func testTogglingUnclassifiedAutomaticallyRefreshesList() {
        // #R020
        XCTAssertTrue(app.staticTexts["Coffee Roasters"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Electric Utility Co"].exists)

        let toggle = uiElement("only-unclassified-toggle")
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        toggle.click()

        // No manual Refresh click: the classified row must appear purely from the toggle's auto-refresh.
        XCTAssertTrue(app.staticTexts["Electric Utility Co"].waitForExistence(timeout: 5))

        toggle.click()

        let utilityAbsent = NSPredicate(format: "exists == false")
        let absentExpectation = expectation(for: utilityAbsent, evaluatedWith: app.staticTexts["Electric Utility Co"])
        wait(for: [absentExpectation], timeout: 5)
    }

    func testNextUnclassifiedScrollsTargetIntoView() {
        // #R025
        // Relaunch with a large page size so `loadAll` returns all 18 fixture rows at once,
        // making the left-hand list tall enough to be scrollable and have rows off-screen.
        app.terminate()
        app.launchEnvironment["TELLER_UI_TEST_PAGE_SIZE"] = "20"
        app.launch()

        disableUnclassifiedFilter()

        // The bottom-most fixture row is txn_018 ("Airline Luggage Fee"). Its presence confirms
        // all 18 rows loaded on one page after the toggle-triggered refresh.
        XCTAssertTrue(app.staticTexts["Airline Luggage Fee"].waitForExistence(timeout: 5))

        let list = app.scrollViews["transaction-list"].firstMatch
        XCTAssertTrue(list.waitForExistence(timeout: 5))

        // Scroll the list aggressively toward the bottom so txn_001 is pushed off the top
        // of the visible viewport. This is the pre-condition that makes #R025 observable.
        list.scroll(byDeltaX: 0, deltaY: -1500)

        let topRow = app.descendants(matching: .any)
            .matching(identifier: "transaction-row-txn_001").firstMatch
        XCTAssertTrue(topRow.waitForExistence(timeout: 5))

        // Confirm the pre-condition via frame comparison: the row should now sit above the
        // list's visible frame after scrolling.
        var outOfViewConfirmed = false
        for _ in 0..<20 {
            let listFrame = list.frame
            let rowFrame = topRow.frame
            if !listFrame.intersects(rowFrame) || rowFrame.maxY < listFrame.minY {
                outOfViewConfirmed = true
                break
            }
            Thread.sleep(forTimeInterval: 0.1)
        }
        XCTAssertTrue(
            outOfViewConfirmed,
            "Test pre-condition failed: txn_001 must be scrolled off-screen before Next Unclassified is triggered."
        )

        // Trigger Next Unclassified. Click the toolbar button (more robust than a keyboard
        // shortcut after an explicit scroll gesture) — this must both select txn_001 and
        // scroll it back into view per #R025. macOS exposes toolbar items under multiple
        // accessibility queries; use `buttons[...].firstMatch` to disambiguate.
        let nextButton = app.buttons["next-unclassified-button"].firstMatch
        XCTAssertTrue(nextButton.waitForExistence(timeout: 5))
        nextButton.click()

        // Verify the selection change actually happened by checking the detail pane header.
        XCTAssertTrue(app.staticTexts["Transaction txn_001"].waitForExistence(timeout: 5))

        // The row must now be scrolled so its frame intersects the list's visible frame. We
        // poll across several attempts to allow the scroll animation to complete.
        var scrolledIntoView = false
        for _ in 0..<20 {
            let listFrame = list.frame
            let rowFrame = topRow.frame
            if listFrame.intersects(rowFrame) && rowFrame.maxY >= listFrame.minY && rowFrame.minY <= listFrame.maxY {
                scrolledIntoView = true
                break
            }
            Thread.sleep(forTimeInterval: 0.25)
        }
        XCTAssertTrue(
            scrolledIntoView,
            "Next Unclassified must scroll txn_001 back into the visible list frame (#R025)."
        )
    }

    func testDetailHeaderShowsTransactionIdentifier() {
        // #R030
        let rowLabel = app.staticTexts["Coffee Roasters"]
        XCTAssertTrue(rowLabel.waitForExistence(timeout: 5))
        rowLabel.click()

        XCTAssertTrue(app.staticTexts["Transaction txn_001"].waitForExistence(timeout: 5))
    }

    private func disableUnclassifiedFilter() {
        let toggle = uiElement("only-unclassified-toggle")
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        toggle.click()
        // #R020 auto-refresh brings the classified fixture row into the list.
        XCTAssertTrue(app.staticTexts["Electric Utility Co"].waitForExistence(timeout: 5))
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
