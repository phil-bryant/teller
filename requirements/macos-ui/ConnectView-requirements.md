# Transaction Classifier Connect View Requirements

## Scope

Applies to `src/macos-ui/Sources/TransactionClassifier/ConnectView.swift` and `src/macos-ui/Sources/TransactionClassifier/ConnectViewModel.swift`.

R001  Statement: Connect tab must present a plain-language connections list.
Design: `ConnectView` renders a single `Financial Institution Connections` list with institution and connection ID rows bound to `selectedContextKey`.
Tests:
- R001-T01: Launch Connect tab and verify the connections list renders institution and connection ID rows.
- R001-T02: Load view model and verify populated contexts seed an initial selection and ready status.

R005  Statement: Primary connection management actions must be Add, Edit, and Delete.
Design: UI exposes exactly three primary actions; `Add` starts `ConnectAction.add`, `Edit` starts `ConnectAction.reconnect` for the selected connection, and `Delete` triggers removal flow.
Tests:
- R005-T01: Start edit from a selected connection and verify reconnect session targets the selected key.
- R005-T02: Start add action and verify add session launches with empty target key.

R010  Statement: Delete action must require explicit confirmation before mutation.
Design: `confirmationDialog` gates destructive delete and only executes removal when user confirms the destructive action.
Tests:
- R010-T01: Execute confirmed delete and verify selected connection is removed from view-model contexts.

R015  Statement: Connect WebView flow must open Teller Connect and bridge success/error/exit events back to Swift state.
Design: `ConnectWebFlowView` builds a local HTML launcher for Teller Connect JS, captures token/enrollment/institution hints on success, and routes success/exit/error payloads through `WKScriptMessageHandler` callbacks.
Tests:
- R015-T01: Start a connect session and verify sheet presentation plus message handling updates status or error paths.

R020  Statement: Edit action must enforce selected-connection prerequisites.
Design: Reconnect/edit session start requires a selected context with enrollment ID and surfaces validation errors otherwise.
Tests:
- R020-T01: Attempt edit session start with missing/invalid selection and verify validation error text.
- R020-T02: Verify valid selection opens reconnect session scoped to that connection.

R025  Statement: Initial load must hydrate service status and contexts on view presentation.
Design: `.task` invokes `loadAll()` once when Connect view appears; view model concurrently fetches status and contexts, seeds selection, and keeps setup diagnostics non-blocking for the Add/Edit/Delete surface.
Tests:
- R025-T01: Open Connect tab and verify status/contexts load without additional setup actions.
- R025-T02: Simulate service failure and verify user-facing "could not load connections" status and error banner.

## Changelog

- 2026-05-02: Added Swift replacement requirements for connect UI and state-management behavior previously documented for shell/token-server UI flows.
- 2026-05-23: Reframed Connect tab requirements around Add/Edit/Delete-first UX and plain-language status behavior.
