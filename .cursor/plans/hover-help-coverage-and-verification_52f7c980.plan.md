---
name: hover-help-coverage-and-verification
overview: Add macOS hover-help text to all interactive controls in the TransactionClassifier UI launched by `21_run_classification_macos-ui.sh`, then add XCUITest coverage so `13_run_macos_ui_regression_tests.sh` verifies tooltip display behavior.
todos:
  - id: inventory-controls
    content: Catalog all interactive controls across Match & Classify, Manage Categories, and Connect tabs.
    status: completed
  - id: add-help-text
    content: Add/normalize `.help(...)` text on every interactive control in ContentView and ConnectView.
    status: completed
  - id: stabilize-selectors
    content: Add any missing accessibility identifiers needed for deterministic tooltip assertions.
    status: completed
  - id: add-hover-scenario
    content: Implement XCUITest scenario that hovers each control and asserts tooltip display/content.
    status: completed
  - id: wire-10-runner
    content: Update `13_run_macos_ui_regression_tests.sh` scenario mapping/count if required for new hover scenario.
    status: completed
  - id: update-requirements
    content: Update requirements docs for ContentView, ConnectView, and 10_ regression script to reflect hover-help requirement and tests.
    status: completed
isProject: false
---

# Add Hover Help Coverage + 10_ Verification

## Scope and target files
- UI control coverage will be implemented in:
  - [`/Users/phil/local/src/teller/macos-ui/Sources/TransactionClassifier/ContentView.swift`](/Users/phil/local/src/teller/macos-ui/Sources/TransactionClassifier/ContentView.swift)
  - [`/Users/phil/local/src/teller/macos-ui/Sources/TransactionClassifier/ConnectView.swift`](/Users/phil/local/src/teller/macos-ui/Sources/TransactionClassifier/ConnectView.swift)
- Hover-verification in regression flow will be implemented in:
  - [`/Users/phil/local/src/teller/macos-ui/UITests/TransactionClassifierUITests.swift`](/Users/phil/local/src/teller/macos-ui/UITests/TransactionClassifierUITests.swift)
  - [`/Users/phil/local/src/teller/13_run_macos_ui_regression_tests.sh`](/Users/phil/local/src/teller/13_run_macos_ui_regression_tests.sh) (scenario list wiring if needed)
- Requirements traceability updates will be made in:
  - [`/Users/phil/local/src/teller/requirements/macos-ui/ContentView-requirements.md`](/Users/phil/local/src/teller/requirements/macos-ui/ContentView-requirements.md)
  - [`/Users/phil/local/src/teller/requirements/macos-ui/ConnectView-requirements.md`](/Users/phil/local/src/teller/requirements/macos-ui/ConnectView-requirements.md)
  - [`/Users/phil/local/src/teller/requirements/13_run_macos_ui_regression_tests-requirements.md`](/Users/phil/local/src/teller/requirements/13_run_macos_ui_regression_tests-requirements.md)

## Implementation approach
- Inventory every interactive control currently exposed in all 3 tabs (Match & Classify, Manage Categories, Connect), including toolbar actions, form fields, toggles, pickers, and action buttons.
- Add missing `.help("...")` text for each interactive control and normalize wording for consistency (action-oriented, short, explicit about side effects).
- Where an interaction currently lacks a stable selector for test automation, add/standardize accessibility identifiers so tooltip assertions can target controls deterministically.
- Add a dedicated smoke-suite scenario in XCUITest that:
  - navigates through all tabs,
  - hovers each targeted control,
  - asserts tooltip visibility/content for each control.
- Update `13_run_macos_ui_regression_tests.sh` scenario mapping if a new smoke step is introduced (and keep selector semantics `N`, `N,M`, `N-M` intact).

## Verification strategy (requested: UI hover assertions)
- Run the XCUITest smoke suite via `13_run_macos_ui_regression_tests.sh` with the hover-help step included.
- Prefer focused iteration using numeric scenario selection during development, then run the full suite for final confirmation.
- Confirm no regressions to existing smoke scenarios and shortcut/help-menu checks.

## Notes on existing code anchors
- Existing controls already carrying `.help(...)` (e.g., badges and score hints) in `ContentView.swift` will be preserved and harmonized with new control-level help text.
- Existing smoke-scenario runner pattern (`scenarioCount` + switch dispatch in `testMacOSUISmokeSuite`) will be extended rather than restructured to minimize risk.
