# Transaction Classifier Connect View Requirements

## Scope

Applies to `macos-ui/Sources/TransactionClassifier/ConnectView.swift` and `macos-ui/Sources/TransactionClassifier/ConnectViewModel.swift`.

R001  Statement: Connect tab must show local enrollment contexts and support explicit refresh.
Design: `ConnectView` renders a selectable contexts list with institution/enrollment display fields and a refresh action that triggers `ConnectViewModel.refreshContexts()`.
Tests:
- R001-T01: Launch Connect tab and verify context list renders institution/enrollment rows.
- R001-T02: Trigger refresh and verify status reflects updated context count.

R005  Statement: Management actions must be available directly in UI for connect, reconnect, add, and delete flows.
Design: View buttons invoke `startConnect(action:)` for capture/reconnect/add and `deleteSelectedContext()` for removal, with disable rules based on busy state and reconnect eligibility.
Tests:
- R005-T01: Select a context with enrollment id and verify reconnect action is enabled.
- R005-T02: Verify delete is disabled when no context is selected and enabled for selected rows.

R010  Statement: Delete action must require explicit confirmation before mutation.
Design: `confirmationDialog` gates destructive delete and only executes removal when user confirms the destructive action.
Tests:
- R010-T01: Attempt delete and verify confirmation appears before any context removal occurs.

R015  Statement: Connect WebView flow must open Teller Connect and bridge success/error/exit events back to Swift state.
Design: `ConnectWebFlowView` builds a local HTML launcher for Teller Connect JS, captures token/enrollment/institution hints on success, and routes success/exit/error payloads through `WKScriptMessageHandler` callbacks.
Tests:
- R015-T01: Start a connect session and verify sheet presentation plus message handling updates status or error paths.

R020  Statement: Manual token save flow must persist entered token data through the selected action.
Design: Manual token/enrollment/institution fields normalize whitespace and call `saveToken(...)`; reconnect requires a selected context while capture/add allow direct save.
Tests:
- R020-T01: Enter a manual token and verify save action updates status and saved token path.
- R020-T02: Attempt reconnect save with no selection and verify validation error text is shown.

R025  Statement: Initial load must hydrate service status and contexts on view presentation.
Design: `.task` invokes `loadAll()` once when Connect view appears; view model concurrently fetches status and contexts, seeds selection, and reflects server-reported errors.
Tests:
- R025-T01: Open Connect tab and verify status/contexts load without explicit user refresh.
- R025-T02: Simulate service failure and verify "Connect service unavailable" state and error banner rendering.

## Changelog

- 2026-05-02: Added Swift replacement requirements for connect UI and state-management behavior previously documented for shell/token-server UI flows.
