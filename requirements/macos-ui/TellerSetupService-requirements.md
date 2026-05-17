# Transaction Classifier Teller Setup Service Requirements

## Scope

Applies to `macos-ui/Sources/TransactionClassifier/TellerSetupService.swift` and `macos-ui/Sources/TransactionClassifier/ConnectViewModel.swift`.

R001  Statement: Native setup must report local Teller file readiness without shell scripts.
Design: `TellerSetupService.loadSnapshot()` inspects `~/.teller` paths and returns availability for app id, cert, key, and token to drive Connect setup status.
Tests:
- R001-T01: Seed a temp `.teller` directory and verify snapshot booleans/path fields match expected file presence.
- R001-T02: Verify connect view-model setup state reflects snapshot readiness changes from Teller setup service.

R005  Statement: Native setup must support application-id provisioning in-app.
Design: `saveApplicationID(...)` writes `application_id.txt` under `~/.teller` after whitespace normalization and validation.
Tests:
- R005-T01: Save a non-empty app id and verify file contents/path and success status.
- R005-T02: Submit empty app id and verify validation failure.

R010  Statement: Native setup must support auth-token provisioning in-app.
Design: `saveAuthToken(...)` writes `auth_token.json` payload as `{"current":"..."}` with strict validation.
Tests:
- R010-T01: Save a token and verify JSON payload includes `current`.
- R010-T02: Submit empty token and verify validation failure.

R015  Statement: Native setup writes must enforce restrictive permissions on Teller setup files.
Design: setup writes ensure `~/.teller` mode `700` and destination files mode `400`.
Tests:
- R015-T01: After save operations, verify directory/file mode bits are `700` and `400`.

R020  Statement: Native setup must run Teller smoke checks using local mTLS credentials.
Design: `runSmokeCheck()` requires app id/cert/key, calls `/institutions`, and optionally calls `/accounts` when token exists.
Tests:
- R020-T01: Stub curl for institutions/accounts and verify success status propagation.
- R020-T02: Verify missing setup prerequisites fail with actionable validation errors.

R025  Statement: Native setup smoke status must preserve non-fatal token warnings.
Design: accounts non-200 returns warning text while keeping institutions success, and missing token reports setup guidance.
Tests:
- R025-T01: Return non-200 accounts code and verify warning text is populated.
- R025-T02: Run without token and verify warning indicates token capture is required.

## Changelog

- 2026-05-14: Migrated step-18 Teller setup behavior from shell workflow into native macOS UI service/view-model ownership.
