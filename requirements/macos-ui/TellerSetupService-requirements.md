# Transaction Classifier Teller Setup Service Requirements

## Scope

Applies to `macos-ui/Sources/TransactionClassifier/TellerSetupService.swift` and `macos-ui/Sources/TransactionClassifier/ConnectViewModel.swift`.

R001  Statement: Native setup must report local Teller file readiness without shell scripts.
Design: `TellerSetupService.loadSnapshot()` inspects `~/.teller` paths and returns availability for app id, cert, key, and token to drive Connect setup status.
Tests:
- Seed a temp `.teller` directory and verify snapshot booleans/path fields match expected file presence.

R005  Statement: Native setup must support application-id provisioning in-app.
Design: `saveApplicationID(...)` writes `application_id.txt` under `~/.teller` after whitespace normalization and validation.
Tests:
- Save a non-empty app id and verify file contents/path and success status.
- Submit empty app id and verify validation failure.

R010  Statement: Native setup must support auth-token provisioning in-app.
Design: `saveAuthToken(...)` writes `auth_token.json` payload as `{"current":"..."}` with strict validation.
Tests:
- Save a token and verify JSON payload includes `current`.
- Submit empty token and verify validation failure.

R015  Statement: Native setup writes must enforce restrictive permissions on Teller setup files.
Design: setup writes ensure `~/.teller` mode `700` and destination files mode `400`.
Tests:
- After save operations, verify directory/file mode bits are `700` and `400`.

R020  Statement: Native setup must run Teller smoke checks using local mTLS credentials.
Design: `runSmokeCheck()` requires app id/cert/key, calls `/institutions`, and optionally calls `/accounts` when token exists.
Tests:
- Stub curl for institutions/accounts and verify success status propagation.
- Verify missing setup prerequisites fail with actionable validation errors.

R025  Statement: Native setup smoke status must preserve non-fatal token warnings.
Design: accounts non-200 returns warning text while keeping institutions success, and missing token reports setup guidance.
Tests:
- Return non-200 accounts code and verify warning text is populated.
- Run without token and verify warning indicates token capture is required.

## Changelog

- 2026-05-14: Migrated step-18 Teller setup behavior from shell workflow into native macOS UI service/view-model ownership.
