# Transaction Classifier Content View Requirements

## Scope

Applies to `src/macos-ui/Sources/TransactionClassifier/ContentView.swift`.

R001  Statement: Render transaction triage UI as a split view.
Design: `NavigationSplitView` presents transaction list controls on the primary side and selected transaction details on the secondary side.
Tests:
- R001-T01: Launch app and verify list/detail panes both render and respond to selection changes.

R010  Statement: Support keyboard-first interaction shortcuts.
Design: Match & Classify pane-local controls expose command shortcuts for next unclassified (`Cmd+]`) and undo (`Cmd+Z`) without relying on global toolbar placement.
Tests:
- R010-T01: Trigger each shortcut and verify the corresponding view-model action executes; specifically for `Cmd+]`, selecting fixture row `txn_002` must advance primary selection to the next unclassified fixture row (`txn_003`) without stalling.

R055  Statement: Match & Classify toolbar controls must be tab-scoped.
Design: `Next Unclassified` only renders on the Match & Classify tab to avoid presenting workflow actions in unrelated tabs (such as Manage Categories).
Tests:
- R055-T01: Switch to Manage Categories and verify `next-unclassified-button` is absent.

R060  Statement: Connect tab must not expose a misleading Undo action.
Design: Undo is scoped to Match & Classify interactions and remains hidden on non-classification tabs, including Connect and Manage Categories.
Tests:
- R060-T01: Switch to Connect and verify `undo-button` is absent.
- R060-T02: Switch to Manage Categories and verify `undo-button` is absent.

R070  Statement: Tab bar must present Connect, Manage Categories, and Match & Classify in that order.
Design: `TabView` child order is Connect first, Manage Categories second, Match & Classify third so enrollment setup precedes category maintenance and transaction triage.
Tests:
- R070-T01: Inspect `ContentView.swift` and verify Connect tab items appear before Manage Categories, which appear before Match & Classify.

## Changelog

- 2026-05-30: Added R070 for tab bar order: Connect, Manage Categories, Match & Classify.
- 2026-05-29: Match action bar button labels updated to Confirm, Override, No-email, Clear (see MatchAndClassifyViews R045); R030 no longer duplicates transaction id in classification actions.
- 2026-04-23: Added Swift-side requirements for `ContentView.swift` from macOS classifier implementation.
- 2026-04-23: Added R020 (auto-refresh on Unclassified toggle), R025 (scroll-to-selection), and R030 (detail header includes transaction id).
- 2026-05-19: Added R035 (auto-scroll email body to transaction amount).
- 2026-05-19: Added R040 (category multi-select and bulk delete in Manage Categories).
- 2026-05-19: Added R045 (Clear match action to the right of Mark no-email).
- 2026-05-25: Added R050 (manual long-list row selection must not auto-recenter).
- 2026-05-25: Added R055/R060 for tab-scoped toolbar controls (hide Next Unclassified on Manage Categories, hide Undo on Connect).
- 2026-05-25: Added R065 (candidates search section title uses `Search Email`).
- 2026-05-26: Split non-shell requirements into feature-specific requirement docs after `ContentView.swift` view extraction.
