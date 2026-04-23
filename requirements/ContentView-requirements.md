# Transaction Classifier Content View Requirements

## Scope

Applies to `macos-ui/Sources/TransactionClassifier/ContentView.swift`.

R001  Statement: Render transaction triage UI as a split view.
Design: `NavigationSplitView` presents transaction list controls on the primary side and selected transaction details on the secondary side.
Tests:
- Launch app and verify list/detail panes both render and respond to selection changes.

R005  Statement: Provide inline search and filtering controls.
Design: Header controls include `TextField` search, `onlyUnclassified` toggle, and refresh action bound to view-model reload.
Tests:
- Enter search text and enable unclassified filter; verify view model reload path is invoked and list narrows accordingly.

R010  Statement: Support keyboard-first interaction shortcuts.
Design: Toolbar exposes command shortcuts for focus search (`Cmd+F`), next unclassified (`Cmd+]`), and undo (`Cmd+Z`).
Tests:
- Trigger each shortcut and verify corresponding view-model action executes.

R015  Statement: Support detail-pane classification edits for current selection.
Design: Detail pane provides apply and clear actions bound to selected rows and currently chosen category.
Tests:
- Select one or more rows, apply a category, then clear classification and verify row-level status updates.

## Changelog

- 2026-04-23: Added Swift-side requirements for `ContentView.swift` from macOS classifier implementation.
