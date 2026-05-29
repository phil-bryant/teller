---
name: search-email-tab-order-updates
overview: Document and verify Search Email keyboard Tab order so focus moves Subject -> Body keyword -> Sender -> Start date, with regression coverage in source tests and macOS UI tests.
todos:
  - id: req-tab-order
    content: Add Search Email Tab-order acceptance criteria to MatchAndClassifyViews requirements
    status: completed
  - id: source-tests-tab-order
    content: Add/update MatchAndClassifyViews requirements tests to assert subject -> body -> sender -> start-date ordering
    status: completed
  - id: ui-test-tab-navigation
    content: Add UITest tab-navigation assertions across Search Email fields
    status: completed
  - id: runner-traceability
    content: Update t14 runner mapping and requirements traceability if scenario list/count changes
    status: completed
  - id: focus-chain-if-needed
    content: Add explicit focus chain in MatchAndClassifyViews only if UITest shows default Tab traversal is unstable
    status: completed
isProject: false
---

# Search Email Tab Order Updates

## Goal
Ensure Search Email keyboard navigation is explicitly specified and regression-tested so Tab traversal follows: Subject -> Body keyword -> Sender -> Start date (then End date).

## What to change

- Update requirements in [`/Users/phil/local/src/teller/requirements/macos-ui/MatchAndClassifyViews-requirements.md`](/Users/phil/local/src/teller/requirements/macos-ui/MatchAndClassifyViews-requirements.md) to add explicit Tab-order acceptance criteria under the Search Email requirement set.
- Update source-level requirements tests in [`/Users/phil/local/src/teller/src/macos-ui/Tests/TransactionClassifierTests/MatchAndClassifyViewsRequirementsTests.swift`](/Users/phil/local/src/teller/src/macos-ui/Tests/TransactionClassifierTests/MatchAndClassifyViewsRequirementsTests.swift):
  - add/adjust ordering assertions for Search Email field identifiers in the intended sequence;
  - add a focused helper assertion (similar to existing ordering helpers) that validates source order for `mailcart-search-subject-field`, `mailcart-search-body-field`, `mailcart-search-sender-field`, and `mailcart-search-start-date-field`.
- Extend macOS UI regression coverage in [`/Users/phil/local/src/teller/src/macos-ui/UITests/TransactionClassifierUITests.swift`](/Users/phil/local/src/teller/src/macos-ui/UITests/TransactionClassifierUITests.swift):
  - add a scenario (or expand advanced email scenario) that tabs from Subject to Body keyword to Sender to Start date and asserts focus progression.
- If scenario indexing changes, update scenario wiring in [`/Users/phil/local/src/teller/tests/t14_run_macos_ui_regression_tests.sh`](/Users/phil/local/src/teller/tests/t14_run_macos_ui_regression_tests.sh) and requirement traceability in [`/Users/phil/local/src/teller/requirements/t14_run_macos_ui_regression_tests-requirements.md`](/Users/phil/local/src/teller/requirements/t14_run_macos_ui_regression_tests-requirements.md).
- Implement explicit focus chaining in [`/Users/phil/local/src/teller/src/macos-ui/Sources/TransactionClassifier/MatchAndClassifyViews.swift`](/Users/phil/local/src/teller/src/macos-ui/Sources/TransactionClassifier/MatchAndClassifyViews.swift) only if runtime Tab behavior proves non-deterministic under SwiftUI default traversal.

## Validation
- Run the targeted requirements test suite for `MatchAndClassifyViewsRequirementsTests`.
- Run the relevant UITest scenario(s) through the existing t14 regression harness path to confirm Tab traversal behavior is stable.

## Notes
- Current field declaration order already aligns with the requested sequence; this work primarily codifies and locks behavior with requirements and tests, then adds UI focus-control only if needed for deterministic runtime behavior.