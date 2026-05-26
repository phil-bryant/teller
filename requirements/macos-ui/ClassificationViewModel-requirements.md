# Transaction Classification ViewModel Requirements

## Scope

Applies to `src/macos-ui/Sources/TransactionClassifier/ClassificationViewModel.swift`.

R001  Statement: Load categories and initial transaction page together.
Design: `loadAll()` concurrently fetches categories and the first transaction page (`pageSize` 150), requests the list with `includeTotal: false` (API R072), assigns rows, updates picker/status, then clears `busy` before kicking off background work. Accurate totals arrive via `refreshTransactionTotal()` (`countOnly: true`). Candidate/email side-pane loads run in a detached task after `busy` is cleared so the transaction-list spinner does not wait on match/message fetches.
Tests:
- R001-T01: Invoke `loadAll()` and verify categories, transactions, totals, and status text all update from fetched payloads.
- R001-T02: Verify the first `fetchTransactions` call uses `includeTotal: false` and `countOnly: false`.
- R001-T03: Verify `busy` is false immediately after `loadAll()` returns even when candidate fetch is still in flight.

R005  Statement: Avoid redundant writes when selected category already matches a row.
Design: `selectedCategoryDidChange()` emits mutations only for selected rows whose category is changing.
Tests:
- R005-T01: Select mixed rows where one already has target category and verify only changed rows are sent to save API.

R010  Statement: Use optimistic updates with rollback on save errors.
Design: `apply(...)` marks rows saving/saved, records undo payloads, and restores previous classifications plus failure state when API write fails.
Tests:
- R010-T01: Save a selection with mocked API failure and verify prior classifications are restored with failed row state.

R015  Statement: Support keyboard-oriented triage progression and undo.
Design: `nextUnclassified()` moves selection to next unclassified row, and `undoLast()` replays prior category values from the undo stack.
Tests:
- R015-T01: Advance from a classified row and verify selection moves to next unclassified row; then save+undo and verify category restoration.

R020  Statement: Append additional transaction pages without duplicate rows.
Design: `loadMore()` fetches by current offset and `mergeTransactions(...)` appends only unseen transaction IDs.
Tests:
- R020-T01: Load first page then next page and verify combined list preserves unique transaction IDs and updated status metadata.

R025  Statement: Default the Unclassified filter to enabled so the first load shows only unclassified rows.
Design: `onlyUnclassified` is initialized to `true` so `loadAll()` filters out already-classified transactions on the first fetch.
Tests:
- R025-T01: Launch app in UI-testing mode and verify only unclassified fixture rows appear in the list and the Unclassified toggle reads as on.

R030  Statement: Delete one or more selected categories from the category editor.
Design: `deleteSelectedCategories()` iterates `categoryEditorSelection`, calls `deleteCategory` for each id, reloads categories, clears selection, and reports partial failures when some deletes fail.
Tests:
- R030-T01: Select two categories with a mock API, invoke bulk delete, and verify both delete calls are made and the selection clears.

R035  Statement: Support clearing a human-reviewed match back to unmatched.
Design: `clearSelectedMatch()` deactivates the active match for the primary selected transaction via the classifier API (by `match_id` when present, otherwise by `transaction_id`). `canClearSelectedMatch` is true when the selected transaction has an active match row that can be cleared. On success the view model reloads transactions and clears match-review status text; on failure it surfaces the API error in `matchReviewErrorText`.
Tests:
- R035-T01: Select a transaction with an active human-reviewed match, invoke `clearSelectedMatch()`, and verify the clear API is called and the row no longer carries match metadata after reload.
- R035-T02: Select a transaction with no active match and verify `canClearSelectedMatch` is false.

R040  Statement: Debounce email search in the candidates pane and surface results or errors.
Design: `searchMailcartIfNeeded()` trims the query, debounces non-empty input (~250ms), calls `searchMessages(query:limit:)`, and updates `mailcartSearchResults` / `mailcartSearchErrorText`. An empty query clears results and errors.
Tests:
- R040-T01: Set a non-empty `mailcartSearchQuery`, await search, and verify results populate from the API response.
- R040-T02: Simulate a search API failure and verify `mailcartSearchErrorText` is set and results clear.

R075  Statement: Refresh accurate transaction totals after the fast first paint.
Design: `refreshTransactionTotal()` calls `fetchTransactions` with `countOnly: true`, `includeTotal: true`, `limit: 1`, and `offset: 0`, then updates `totalTransactions` and status text without blocking the initial list render.
Tests:
- R075-T01: After `loadAll()`, allow background tasks to run and verify a `countOnly` fetch updates `totalTransactions` from the API.

R080  Statement: Optional stderr profiling for transaction-list load and first render.
Design: When `TELLER_UI_PROFILE_TRANSACTION_LIST=true`, `TransactionListProfiler` logs `[teller-ui-profile]` lines for load start, categories done, transaction fetch duration, state assignment, `busy` cleared, and first list `onAppear` render timing.
Tests:
- R080-T01: Verify profiling is disabled unless the environment variable is set to `true`.

## Changelog

- 2026-04-23: Added Swift-side requirements for `ClassificationViewModel.swift` to replace prior plan-only coverage.
- 2026-04-23: Added R025 to default the Unclassified filter to enabled on initial load.
- 2026-05-19: Added R030 (bulk category delete from category editor selection).
- 2026-05-19: Added R035 (clear human-reviewed match back to unmatched).
- 2026-05-19: Added R040 (debounced email search in candidates pane).
- 2026-05-26: Expanded R001 for fast first load (R072 client, busy cleared before side pane); added R075 and R080.
