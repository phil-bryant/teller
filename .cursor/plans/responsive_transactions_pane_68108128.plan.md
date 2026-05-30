---
name: Responsive Transactions Pane
overview: Make the Transactions lane responsive so filter controls and action buttons wrap instead of compressing at narrow widths, while preserving existing identifiers and behavior.
todos:
  - id: refactor-transactions-pane-layout
    content: Refactor Transactions pane filter/action rows to responsive auto-wrap layout in MatchAndClassifyViews.swift
    status: completed
  - id: preserve-a11y-and-ordering
    content: Ensure all existing accessibility identifiers and control ordering semantics remain intact
    status: completed
  - id: add-responsive-regression-tests
    content: Add/adjust requirements and snapshot tests for narrow-width wrapping behavior
    status: completed
  - id: run-targeted-ui-tests
    content: Run focused macOS UI/unit snapshot tests for transaction pane layout regressions
    status: completed
isProject: false
---

# Responsive Transactions Lane Wrapping

## Goal
Implement responsive wrapping in the Transactions pane so controls do not visually collapse when the left split pane is narrowed.

## Implementation approach
- Update [`src/macos-ui/Sources/TransactionClassifier/MatchAndClassifyViews.swift`](src/macos-ui/Sources/TransactionClassifier/MatchAndClassifyViews.swift) to make the Transactions pane rows adaptive:
  - Keep current control order and accessibility identifiers.
  - Replace rigid `HStack` groupings for the filter rows and action row with a width-aware layout that wraps at a defined breakpoint (auto-wrap behavior).
  - Preserve existing fixed widths where useful (`dateFieldWidth`, `amountFieldWidth`, `institutionPickerWidth`) but allow row flow to wrap naturally rather than squeeze.
- Ensure action buttons (`Next Unclassified`, `Refresh`, `Load more`) wrap across lines at narrow widths in the same left-to-right semantic order.
- Keep all existing command hookups unchanged (`loadAll`, `loadMore`, `nextUnclassified`) so functionality remains identical.

## Validation
- Update/add tests in [`src/macos-ui/Tests/TransactionClassifierTests/MatchAndClassifyViewsRequirementsTests.swift`](src/macos-ui/Tests/TransactionClassifierTests/MatchAndClassifyViewsRequirementsTests.swift):
  - Verify responsive container usage for Transactions pane controls.
  - Confirm key identifiers remain present and control/action ordering invariants are preserved.
- Add or extend snapshot coverage in [`src/macos-ui/Tests/TransactionClassifierSnapshotTests/ContentViewSnapshotTests.swift`](src/macos-ui/Tests/TransactionClassifierSnapshotTests/ContentViewSnapshotTests.swift) with a narrower app width variant to catch future control-smush regressions.
- Run targeted test suites for transaction pane requirements and snapshots to verify no behavioral regressions.

## Notes
- This is a UI-only layout change; model/data logic should remain untouched.
- Existing pane minimum widths in the split view stay as-is unless narrow snapshot evidence suggests a small adjustment is needed for better ergonomics.