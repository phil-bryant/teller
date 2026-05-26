# Transaction Classifier Content View Requirements

## Scope

Applies to `src/macos-ui/Sources/TransactionClassifier/ContentView.swift`.

R001  Statement: Render transaction triage UI as a split view.
Design: `NavigationSplitView` presents transaction list controls on the primary side and selected transaction details on the secondary side.
Tests:
- R001-T01: Launch app and verify list/detail panes both render and respond to selection changes.

R005  Statement: Provide inline search and filtering controls.
Design: Header controls include `TextField` search, `onlyUnclassified` toggle, and refresh action bound to view-model reload.
Tests:
- R005-T01: Enter search text and enable unclassified filter; verify view model reload path is invoked and list narrows accordingly.

R010  Statement: Support keyboard-first interaction shortcuts.
Design: Toolbar exposes command shortcuts for next unclassified (`Cmd+]`) and undo (`Cmd+Z`).
Tests:
- R010-T01: Trigger each shortcut and verify the corresponding view-model action executes.

R015  Statement: Support detail-pane classification edits for current selection.
Design: Detail pane provides apply and clear actions bound to selected rows and currently chosen category.
Tests:
- R015-T01: Select one or more rows, apply a category, then clear classification and verify row-level status updates.

R020  Statement: Toggling the Unclassified filter in either direction automatically reloads the transaction list.
Design: `ContentView` observes `viewModel.onlyUnclassified` via `.onChange` and invokes `loadAll()` whenever the switch flips so users do not have to press Refresh.
Tests:
- R020-T01: Toggle the Unclassified switch off and on and verify that rows matching the new filter state appear without pressing Refresh.

R025  Statement: Programmatic selection changes scroll the newly-selected row into view.
Design: The transaction list scroll binding only honors view-model-issued pending scroll targets, so Next Unclassified (or other model-driven navigation updates) brings the target row on-screen while preserving manual click-position stability.
Tests:
- R025-T01: With the Unclassified filter off and all fixture pages loaded, scroll the list so the top row is off-screen, trigger Next Unclassified, and verify the newly-selected row becomes hittable in the viewport.

R050  Statement: Manual row selection in long transaction lists must not auto-recenter the list.
Design: `ContentView` only applies programmatic list scrolling when `ClassificationViewModel` marks a pending scroll target (for keyboard navigation actions such as Next Unclassified). User-initiated row clicks update selection without forcing `.scrollPosition` recentering.
Tests:
- R050-T01: With a long loaded list that requires scrolling, navigate to visible middle-list rows, click one or more of those rows, and verify each selected row frame stays effectively stable (no jump-to-center) after selection.

R030  Statement: Detail pane header includes the selected transaction's identifier.
Design: The detail pane renders `Text("Transaction \(selected.transaction_id)")` as its primary header instead of a generic "Transaction" label so the active transaction identifier is always visible.
Tests:
- R030-T01: Select a fixture row and verify the detail pane header displays `Transaction <transaction_id>` matching the selected row.

R035  Statement: When a candidate email body loads, scroll the body pane so the selected transaction's amount is visible.
Design: `EmailBodyContent` receives `scrollToAmount` from the primary transaction. HTML bodies use `EmailBodyWebView` with a navigation delegate that runs `scrollIntoView({ block: 'center', inline: 'center' })` on the best amount match after load; plain-text bodies use `ScrollViewReader` to center the matching line. Amount search prefers lines containing total keywords and uses absolute-value variants (`$15.19`, `15.19`, etc.).
Tests:
- R035-T01: Unit-test amount variant generation and text line selection helpers.
- R035-T02: Select a wide receipt email candidate and verify the order total amount is scrolled into view horizontally and vertically.

R040  Statement: Manage Categories supports multi-select and bulk delete.
Design: `CategoryManagerView` keeps category selection in a `Set<Int>`. Plain click selects one row; Command-click toggles rows in the set. The sidebar header exposes a Delete action enabled when one or more categories are selected. When exactly one category is selected the edit form is active; when multiple are selected the form is disabled and the header shows the selection count.
Tests:
- R040-T01: Command-click two categories and verify Delete is enabled; trigger bulk delete and verify both categories are removed from the list.
- R040-T02: In the Manage Categories smoke edit scenario, clear/replace only the populated Categorization field before saving (`Dining` -> `Dining Updated`) and keep other draft fields paste-only to avoid unnecessary UI latency.

R045  Statement: Match action bar exposes a Clear control to the right of Mark no-email.
Design: `MatchActionsBar` renders Confirm, Override with this email, Mark no-email, then Clear in that order. Clear is bound to `clearSelectedMatch()` and disabled when `canClearSelectedMatch` is false. On success the transaction list reloads and the row shows the unmatched badge (no active human-reviewed match).
Tests:
- R045-T01: Select a transaction with a human-reviewed match, tap Clear, and verify the row badge returns to unmatched and the button is disabled for transactions with no clearable match.

R055  Statement: Match & Classify toolbar controls must be tab-scoped.
Design: `Next Unclassified` only renders on the Match & Classify tab to avoid presenting workflow actions in unrelated tabs (such as Manage Categories).
Tests:
- R055-T01: Switch to Manage Categories and verify `next-unclassified-button` is absent.

R060  Statement: Connect tab must not expose a misleading Undo action.
Design: Undo is scoped to Match & Classify interactions and remains hidden on non-classification tabs, including Connect and Manage Categories.
Tests:
- R060-T01: Switch to Connect and verify `undo-button` is absent.
- R060-T02: Switch to Manage Categories and verify `undo-button` is absent.

R065  Statement: The candidates search section uses user-facing copy "Search Email".
Design: The candidates pane search section title is `Search Email` to match end-user terminology while keeping Mailcart as an implementation detail.
Tests:
- R065-T01: Open Match & Classify and verify the candidates pane renders a visible `Search Email` section heading above the search field.

## Changelog

- 2026-04-23: Added Swift-side requirements for `ContentView.swift` from macOS classifier implementation.
- 2026-04-23: Added R020 (auto-refresh on Unclassified toggle), R025 (scroll-to-selection), and R030 (detail header includes transaction id).
- 2026-05-19: Added R035 (auto-scroll email body to transaction amount).
- 2026-05-19: Added R040 (category multi-select and bulk delete in Manage Categories).
- 2026-05-19: Added R045 (Clear match action to the right of Mark no-email).
- 2026-05-25: Added R050 (manual long-list row selection must not auto-recenter).
- 2026-05-25: Added R055/R060 for tab-scoped toolbar controls (hide Next Unclassified on Manage Categories, hide Undo on Connect).
- 2026-05-25: Added R065 (candidates search section title uses `Search Email`).
