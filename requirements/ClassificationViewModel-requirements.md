# Transaction Classification ViewModel Requirements

## Scope

Applies to `macos-ui/Sources/TransactionClassifier/ClassificationViewModel.swift`.

R001  Statement: Load categories and initial transaction page together.
Design: `loadAll()` concurrently fetches categories and first-page transactions, then updates derived picker and status state.
Tests:
- Invoke `loadAll()` and verify categories, transactions, totals, and status text all update from fetched payloads.

R005  Statement: Avoid redundant writes when selected category already matches a row.
Design: `selectedCategoryDidChange()` emits mutations only for selected rows whose category is changing.
Tests:
- Select mixed rows where one already has target category and verify only changed rows are sent to save API.

R010  Statement: Use optimistic updates with rollback on save errors.
Design: `apply(...)` marks rows saving/saved, records undo payloads, and restores previous classifications plus failure state when API write fails.
Tests:
- Save a selection with mocked API failure and verify prior classifications are restored with failed row state.

R015  Statement: Support keyboard-oriented triage progression and undo.
Design: `nextUnclassified()` moves selection to next unclassified row, and `undoLast()` replays prior category values from the undo stack.
Tests:
- Advance from a classified row and verify selection moves to next unclassified row; then save+undo and verify category restoration.

R020  Statement: Append additional transaction pages without duplicate rows.
Design: `loadMore()` fetches by current offset and `mergeTransactions(...)` appends only unseen transaction IDs.
Tests:
- Load first page then next page and verify combined list preserves unique transaction IDs and updated status metadata.

## Changelog

- 2026-04-23: Added Swift-side requirements for `ClassificationViewModel.swift` to replace prior plan-only coverage.
