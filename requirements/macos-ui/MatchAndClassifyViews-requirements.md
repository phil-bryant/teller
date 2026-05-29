# Transaction Classifier Match & Classify View Requirements

## Scope

Applies to `src/macos-ui/Sources/TransactionClassifier/MatchAndClassifyViews.swift`.

R005  Statement: Transaction discovery controls belong inside the Transactions pane.
Design: `MatchAndClassifyTransactionsPane` owns transaction-scoped controls: `TextField` search, `onlyUnclassified` toggle, and the advanced transaction filters (date range, institution, amount from R070). To avoid overcrowding, these controls render on four rows inside the pane: (1) search only, (2) start date + min amount + institution picker (label hidden), (3) end date + max amount + unclassified toggle, (4) refresh/load-more actions. The date fields use a shared width token (`Start date` and `End date` equal width), and the amount fields use a shared width token (`Min amount` and `Max amount` equal width).
Tests:
- R005-T01: Enter search text and enable unclassified filter; verify view model reload path is invoked and list narrows accordingly.
- R005-T02: Open Match & Classify and verify search/unclassified plus advanced transaction filter controls render from the Transactions pane container.
- R005-T03: Open Match & Classify and verify the Transactions-pane controls are split across four rows so min/max amount fields are not on the same row as date/institution controls.
- R005-T04: Verify `Start date` and `End date` use the same explicit width token and `Min amount`/`Max amount` use the same explicit width token.

R015  Statement: Support detail-pane classification edits for current selection.
Design: `ClassifySection` in the Classification pane provides category selection plus Apply/Clear/Undo actions bound to selected rows and currently chosen category. Undo is rendered immediately to the right of Clear and remains scoped to Match & Classify interactions. Classification controls are not rendered in the Transactions or Match panes.
Tests:
- R015-T01: Select one or more rows, apply a category, then clear classification and verify row-level status updates.
- R015-T02: Open Match & Classify and verify classification controls (`CategoryTypeaheadField`, Apply to Selected, Clear) are defined in `ClassifySection`.
- R015-T03: Open Match & Classify and verify `undo-button` is rendered in `ClassifySection` to the right of `clear-selection-button`.

R020  Statement: Toggling the Unclassified filter in either direction automatically reloads the transaction list.
Design: `MatchAndClassifyView` observes `viewModel.onlyUnclassified` via `.onChange` and invokes `loadAll()` whenever the switch flips so users do not have to press Refresh.
Tests:
- R020-T01: Toggle the Unclassified switch off and on and verify that rows matching the new filter state appear without pressing Refresh.

R025  Statement: Programmatic selection changes scroll the newly-selected row into view.
Design: The transaction list scroll binding only honors view-model-issued pending scroll targets, so Next Unclassified (or other model-driven navigation updates) brings the target row on-screen while preserving manual click-position stability.
Tests:
- R025-T01: With the Unclassified filter off and all fixture pages loaded, scroll the list so the top row is off-screen, trigger Next Unclassified, and verify the newly-selected row becomes hittable in the viewport.

R030  Statement: Detail pane header includes the selected transaction's identifier.
Design: The detail pane renders `Text("Transaction \(selected.transaction_id)")` as its primary header instead of a generic "Transaction" label so the active transaction identifier is always visible.
Tests:
- R030-T01: Select a fixture row and verify the detail pane header displays `Transaction <transaction_id>` matching the selected row.

R035  Statement: When a candidate email body loads, scroll the body pane so the selected transaction's amount is visible.
Design: `EmailBodyContent` receives `scrollToAmount` from the primary transaction. HTML bodies use `EmailBodyWebView` with a navigation delegate that runs `scrollIntoView({ block: 'center', inline: 'center' })` on the best amount match after load; plain-text bodies use `ScrollViewReader` to center the matching line. Amount search prefers lines containing total keywords and uses absolute-value variants (`$15.19`, `15.19`, etc.).
Tests:
- R035-T01: Unit-test amount variant generation and text line selection helpers.
- R035-T02: Select a wide receipt email candidate and verify the order total amount is scrolled into view horizontally and vertically.

R045  Statement: Match action bar exposes Confirm, Override, No-email, and Clear controls in that order.
Design: `MatchActionsBar` renders four buttons with user-facing labels `Confirm`, `Override`, `No-email`, and `Clear`, bound respectively to `confirmSelectedMatch()`, `overrideSelectedMatch()`, `markSelectedMatchNoEmail()`, and `clearSelectedMatch()`. Each button uses a stable accessibility identifier (`match-confirm-button`, `match-override-button`, `match-no-email-button`, `match-clear-button`). Confirm disables when `canConfirmSelectedMatch` is false; Override when `canOverrideSelectedMatch` is false; No-email when `canMarkSelectedMatchNoEmail` is false; Clear when `canClearSelectedMatch` is false. On successful Clear, the transaction list reloads and the row shows the unmatched badge (no active human-reviewed match).
Tests:
- R045-T01: Select a transaction with a human-reviewed match, tap Clear, and verify the row badge returns to unmatched and the button is disabled for transactions with no clearable match.
- R045-T02: Open Match & Classify with a selected transaction and verify the match action bar renders buttons labeled Confirm, Override, No-email, and Clear in that order.

R050  Statement: Manual row selection in long transaction lists must not auto-recenter the list.
Design: `MatchAndClassifyTransactionsPane` only applies programmatic list scrolling when `ClassificationViewModel` marks a pending scroll target (for keyboard navigation actions such as Next Unclassified). User-initiated row clicks update selection without forcing `.scrollPosition` recentering.
Tests:
- R050-T01: With a long loaded list that requires scrolling, navigate to visible middle-list rows, click one or more of those rows, and verify each selected row frame stays effectively stable (no jump-to-center) after selection.

R065  Statement: The candidates search section uses user-facing copy "Search Email".
Design: The candidates pane search section title is `Search Email` to match end-user terminology while keeping Mailcart as an implementation detail.
Tests:
- R065-T01: Open Match & Classify and verify the candidates pane renders a visible `Search Email` section heading above the search field.

R066  Statement: The middle pane header uses user-facing copy "Transaction - Email Match Candidates".
Design: The candidates pane headline is `Transaction - Email Match Candidates` instead of the generic label `Candidates` so users understand the pane lists email-match options for the selected transaction.
Tests:
- R066-T01: Open Match & Classify and verify the middle pane renders a visible `Transaction - Email Match Candidates` heading above the candidate list.

R067  Statement: The classification section header uses user-facing copy "Transaction Classification".
Design: The right-pane classification picker headline is `Transaction Classification` instead of the generic label `Classify` so users understand that section is for assigning categories to selected transactions.
Tests:
- R067-T01: Open Match & Classify and verify the right pane renders a visible `Transaction Classification` heading above the category typeahead.

R068  Statement: Transaction list actions belong beside the Transactions pane.
Design: `MatchAndClassifyTransactionsPane` renders Next Unclassified, Refresh (bound to `loadAll()`), and Load more (bound to `loadMore()`, disabled when `!canLoadMore || busy`) in the pane header below the Transactions title and count, not in the global filter toolbar or bottom status bar. Next Unclassified is placed to the left of Refresh.
Tests:
- R068-T01: Open Match & Classify and verify `next-unclassified-button`, `refresh-button`, and `load-more-button` are exposed from the transactions pane header.
- R068-T02: Tap Refresh and verify status text reports a loaded transaction count; tap Load more when enabled and verify additional rows append.
- R068-T03: Verify `next-unclassified-button` is declared before `refresh-button` in the Transactions actions row.

R070  Statement: Expose advanced transaction filters for date range, institution, and amount.
Design: `MatchAndClassifyTransactionsPane` renders start/end date fields (`YYYY-MM-DD`), an institution picker (`All institutions` plus distinct `institution_id` values), and min/max amount fields beside the transaction list controls. Each control uses a stable accessibility identifier (`transaction-start-date-field`, `transaction-end-date-field`, `transaction-institution-picker`, `transaction-min-amount-field`, `transaction-max-amount-field`). Changing any advanced filter automatically reloads the transaction list (same UX as the Unclassified toggle).
Tests:
- R070-T01: Open Match & Classify and verify all five advanced transaction filter controls render in the Transactions pane.
- R070-T02: Set a date range and amount bounds that exclude fixture rows, then verify the transaction list narrows without pressing Refresh.
- R070-T03: Exercise each scalar transaction filter independently (`start date`, `end date`, `min amount`, `max amount`) and verify each one changes fixture results as expected.

R072  Statement: Match controls belong in the Match pane.
Design: `CandidatesPane` owns match-scoped controls (`match-review-state-picker` and `match-review-only-unmoved-toggle`) so filtering by match state stays colocated with the candidate list and search controls it governs.
Tests:
- R072-T01: Open Match & Classify and verify the match-state picker and only-unmoved toggle are defined in `CandidatesPane` and omitted from `MatchAndClassifyTransactionsPane`.

R071  Statement: Expose advanced email search fields for subject, body, sender, and date range.
Design: The candidates pane `Search Email` section provides subject, body, sender, and date start/end fields (`YYYY-MM-DD`) with stable accessibility identifiers (`mailcart-search-subject-field`, `mailcart-search-body-field`, `mailcart-search-sender-field`, `mailcart-search-start-date-field`, `mailcart-search-end-date-field`). Date labels use user-facing copy `Start date` and `End date`. Keyboard Tab traversal for Search Email fields follows `Subject -> Body keyword -> Sender -> Start date -> End date`. A guidance hint clarifies that subject/body/sender are scoped filters, start/end dates are inclusive, and filled filters are ANDed. Any field change debounces into the existing Mailcart search path. Search hits remain visible when the user changes the selected transaction (ClassificationViewModel R116).
Tests:
- R071-T01: Open Match & Classify and verify subject/body/sender/start-date/end-date fields render under `Search Email`.
- R071-T02: Enter a subject filter that matches one fixture search hit and verify the hit row appears and can be selected to load the email body.
- R071-T03: Exercise sender search with a fixture sender value and verify the expected hit row appears.
- R071-T04: Exercise sender search with a non-matching sender value and verify no fixture hit rows remain visible.
- R071-T05: Exercise email search by `Body keyword`, `Start date`, and `End date` and verify each filter changes fixture hits as expected.
- R071-T06: Verify `mailcart-search-contract-hint` renders guidance that scoped filters are ANDed and date bounds are inclusive.
- R071-T07: After a successful body-keyword search, select a different transaction and verify the same search hit rows remain listed without retyping criteria.
- R071-T08: Verify Search Email field declaration order keeps Tab traversal as Subject -> Body keyword -> Sender -> Start date -> End date.
- R071-T09: In macOS UI regression, focus Subject and press Tab repeatedly; verify focus advances to Body keyword, Sender, then Start date.

R075  Statement: Email body viewer supports Rendered and Raw modes.
Design: `EmailSection` exposes a segmented body-mode picker (`email-body-mode-picker`) with `Rendered` and `Raw` options (`email-body-mode-rendered`, `email-body-mode-raw`). The default mode is `Rendered` and must reset to `Rendered` when a different email message is selected. In `Rendered` mode, `html_body` is shown via `EmailBodyWebView` and `text_body` is the fallback. In `Raw` mode, body display prefers `text_body`; if plain text is absent, the UI shows raw `html_body` source in monospaced selectable text (not interpreted HTML).
Tests:
- R075-T01: In fixture mode with an email that has both html and text bodies, verify the default view is rendered HTML, switch to Raw and verify text-body raw output, then select a different email and verify mode resets to rendered.

R076  Statement: Confirming a selected candidate preserves right-pane email rendering continuity.
Design: When `Confirm` succeeds for a transaction whose selected candidate still resolves to the same email message id, `EmailSection` keeps showing the previously loaded body while refresh/reload completes. This flow must not replace rendered content with the `email-error` banner for transient post-confirm message refetch failures.
Tests:
- R076-T01: Select a transaction with a loaded candidate email body, press Confirm, and verify the right pane keeps showing email body content while `email-error` remains hidden.

## Changelog

- 2026-05-29: Updated R045 to require compact match action bar labels (`Confirm`, `Override`, `No-email`, `Clear`) with stable accessibility identifiers; added R045-T02.
- 2026-05-29: Added R076 to require post-confirm email-pane continuity (keep rendered body visible; do not surface `email-error` for transient refetch failures).
- 2026-05-28: Added explicit Search Email keyboard Tab order contract and coverage (R071-T08/R071-T09).
- 2026-05-28: Extended R071 so email search hits persist across transaction selection (R071-T07, ViewModel R116).
- 2026-05-27: Added explicit positive/negative sender regression requirements (R071-T03/R071-T04) and split remaining body/date checks into R071-T05.
- 2026-05-27: Moved Next Unclassified into the Transactions actions row (left of Refresh) and moved Undo into the Classification action row (right of Clear); added R015-T03 and R068-T03.
- 2026-05-27: Restored sender search control, relabeled email date fields to `Start date`/`End date`, and expanded R071-T03 coverage to include sender + date bounds.
- 2026-05-27: Updated R071 to remove sender search control from the Match pane; added coverage for body/from/to email search and independent scalar transaction filter checks (R070-T03, R071-T03).
- 2026-05-27: Updated R005 to require equal paired widths for date and amount fields in Transactions-pane rows 2 and 3; added R005-T04.
- 2026-05-27: Adjusted R005 row ordering so row 2 is start/min/institution (label hidden) and row 3 is end/max/unclassified.
- 2026-05-27: Adjusted R005 Transactions-pane row layout to search-only row 1, date+amount row 2, unclassified+institution row 3, actions row 4.
- 2026-05-27: Updated R005 layout guidance to require four Transactions-pane control rows to prevent overcrowding; added R005-T03.
- 2026-05-27: Updated pane ownership requirements so transaction controls live in `MatchAndClassifyTransactionsPane`, match controls live in `CandidatesPane`, and classification controls remain in `ClassifySection`; added R072 and R015-T02.
- 2026-05-26: Added R070 (advanced transaction filters: date range, institution, amount) and R071 (advanced email search: subject, sender, body, date range).
- 2026-05-26: Added R068 (Refresh/Load more beside Transactions pane) and updated R005 for two-row filter toolbar layout.
- 2026-05-26: Added R066 (middle pane title `Transaction - Email Match Candidates`) and R067 (classification section title `Transaction Classification`).
- 2026-05-26: Extracted Match & Classify requirements from `ContentView-requirements.md` after view-file split.
