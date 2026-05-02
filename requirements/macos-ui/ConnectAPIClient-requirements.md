# Transaction Classifier Connect API Client Requirements

## Scope

Applies to `macos-ui/Sources/TransactionClassifier/ConnectAPIClient.swift`.

R001  Statement: Discover local enrollment contexts from default and suffixed Teller files.
Design: `fetchContexts()` reads default files (`auth_token.json`, `enrollment_id.txt`) plus suffixed pairs (`auth_token_<suffix>.json`, `enrollment_id_<suffix>.txt`) and returns deterministic context keys.
Tests:
- Seed default and suffixed files, call `fetchContexts()`, and verify both contexts are returned with stable keys.

R005  Statement: Add mode must persist a new enrollment context without overwriting existing contexts.
Design: `storeToken(...)` in `add` mode derives and sanitizes a suffix from institution hint/enrollment/inferred institution, resolves uniqueness with incrementing suffixes, and writes new token/enrollment files under `~/.teller`.
Tests:
- Call `storeToken(...)` twice in add mode with the same base hint and verify second output uses a distinct suffixed filename.

R010  Statement: Reconnect mode must update only the selected enrollment context.
Design: `storeToken(...)` in `reconnect` mode requires a matching `targetKey` and writes token/enrollment updates to that context's resolved file paths.
Tests:
- Create two local contexts, reconnect one by key, and verify only selected token/enrollment files change.

R015  Statement: Deletion must move only selected local context files to local Trash.
Design: `deleteContext(targetKey:)` resolves one context, moves token and enrollment files into `~/.Trash/teller-enrollment-removals` with timestamped names, and returns remaining contexts.
Tests:
- Delete one suffixed context and verify source files are removed, trash destinations are returned, and non-target contexts remain.

R020  Statement: Connect start sessions must validate prerequisites and action-specific context requirements.
Design: `startSession(...)` requires a non-empty `~/.teller/application_id.txt`, requires selected context with `enrollment_id` for reconnect, and supplies app/environment/enrollment fields for WebView launch.
Tests:
- Verify reconnect without selection or enrollment id fails with explicit validation errors.
- Verify capture/add sessions return empty `targetKey` and `enrollmentId`.

R025  Statement: Token capture writes must enforce restrictive file permissions.
Design: Writes create `~/.teller` with mode `700`, atomically write token/enrollment payloads through temp files, and set destination files to mode `400`.
Tests:
- Store a token and verify directory/file permission bits are restricted as specified.

R030  Statement: Institution inference must remain best-effort and non-fatal.
Design: `inferInstitutionID(...)` attempts Teller identity lookup only when cert/key files exist and returns empty string on command failures, malformed payloads, or missing institution fields.
Tests:
- Omit cert/key files and verify context discovery and token storage continue without throwing.

## Changelog

- 2026-05-02: Added Swift replacement requirements for connect context/session/storage behavior previously documented for shell/token-server flows.
