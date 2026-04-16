# Multi Enrollment Requirements

## Scope

Applies to enrollment selection, CLI-targeted multi-enrollment execution, and Teller ingestion behavior for credit accounts.

## Assumptions

- Teller API remains the ingestion source for this phase.
- `institution_id` values follow Teller institution IDs (for example: `first_ak_bank_trust`, `chase`).
- Existing account/transaction persistence paths remain the system of record.
- Existing single-token users keep `~/.teller/auth_token.json` as the default credential path.

## Non-Goals (This Revision)

- No PDF statement ingestion in this revision.
- No new transaction schema dedicated only to credit cards.

## Requirements

R001  Statement: Accept optional `--institution_id <institution_id>` CLI flag.
Design: Add flag to the ingestion entrypoint and propagate it to enrollment selection logic.
Tests:

- Run with `--institution_id chase` and verify targeted selection path is used.

R005  Statement: Process all enrollments when `--institution_id` is omitted.
Design: Default selection is full enrollment set from enrollment metadata.
Tests:

- Run without the flag and verify all known enrollments are attempted.

R010  Statement: Keep `auth_token.json` as default credential source.
Design: Preserve current single-token execution when no multi-enrollment CLI input is provided.
Tests:

- Run without multi-enrollment arguments and verify current single-enrollment behavior remains unchanged.

R012  Statement: Auto-discover enrollment contexts without enrollment CLI inputs.
Design: Discover contexts from fixed local Teller paths (`auth_token.json`, `enrollment_id.txt`, optional metadata files).
Constraints:

- No enrollment file path CLI argument is required.
- Missing optional metadata must not fail the run.
Tests:
- Run with only default Teller files present and verify ingestion still runs.
- Add optional metadata files and verify contexts are auto-discovered.

R013  Statement: Require only `--institution_id` for targeted enrollment selection.
Design: Use `--institution_id` as the single targeting control and resolve matching enrollment contexts automatically.
Constraints:

- Exact match on institution id for explicit metadata contexts.
- If no explicit metadata match exists, fall back to default context and database-based inference.
Tests:
- Run with `--institution_id chase` and verify non-matching explicit contexts are skipped.
- Run with `--institution_id` where no explicit context exists and verify fallback still attempts ingestion.

R015  Statement: Select enrollments by exact `institution_id` match.
Design: Filter the full selected set (default plus CLI-targeted enrollments) before API calls.
Tests:

- Run with `--institution_id first_ak_bank_trust` and verify only matching enrollment(s) are executed.
- Run with unknown `--institution_id` and verify clean zero-work exit with message.

R020  Statement: Ingest Chase accounts through the existing Teller account flow.
Design: Reuse `/accounts`, `/identity`, `/transactions`, and `/balances` flow without a Chase-specific API client.
Tests:

- With `--institution_id chase`, verify account discovery completes with Teller endpoints only.

R025  Statement: Ingest Chase credit card transactions.
Design: Treat accounts with `type=credit` and `subtype=credit_card` as first-class ingestion targets.
Tests:

- Verify transactions for Chase credit card accounts are fetched and persisted.
- Verify mixed depository/credit institution runs persist both account categories.

R030  Statement: Keep per-enrollment failures isolated.
Design: Record enrollment-scoped errors and continue remaining selected enrollments.
Tests:

- Simulate one disconnected enrollment and verify others still complete.

R035  Statement: Define disconnected-enrollment handling for targeted runs.
Design: If a selected enrollment is disconnected, attempt repair using stored `enrollment_id`; fail that enrollment only on repair failure.
Tests:

- Run targeted institution with disconnected enrollment and verify repair attempt occurs once.

R040  Statement: Preserve backward compatibility for single-enrollment users.
Design: Existing one-token flow must still work without enrollment metadata bootstrapping or migration.
Tests:

- Fresh single-enrollment setup runs unchanged with no additional required args.

R045  Statement: Emit enrollment-scoped observability fields.
Design: Include `institution_id`, `enrollment_id`, account count, transaction count, and status per enrollment in logs.
Tests:

- Verify run output includes one completion line per enrollment with those fields.

R050  Statement: Make `06_capture_teller_token.sh` the enrollment-management entrypoint.
Design: `06_capture_teller_token.sh` MUST expose enrollment management actions instead of only token capture.
Constraints:

- Management actions include listing, deleting, reconnecting, and adding enrollments.
- Existing capture flow remains available as the add/reconnect implementation path.
Tests:
- Run `./06_capture_teller_token.sh --help` and verify management actions are documented.

R055  Statement: List all local enrollments from `06_capture_teller_token.sh`.
Design: Add a list mode that prints each known enrollment with `institution_id` and `enrollment_id`.
Constraints:

- List output MUST include default context (`auth_token.json` + `enrollment_id.txt`) when present.
- List output MUST include suffix contexts (`auth_token_<institution>.json`) when present.
- Missing metadata MUST NOT fail listing; partial rows are allowed.
Tests:
- Run list mode with multiple contexts and verify all known enrollments appear once.
- Run list mode with only default files and verify one default row is shown.

R060  Statement: Delete a selected enrollment from `06_capture_teller_token.sh`.
Design: Add a delete mode keyed by `institution_id` and/or `enrollment_id` to remove local enrollment context files.
Constraints:

- Delete action MUST require explicit selection and confirmation.
- Delete action MUST only remove targeted local context and MUST NOT delete other enrollments.
- Delete action MUST NOT call Teller APIs that permanently remove server-side enrollment records.
Tests:
- Delete one enrollment in a multi-enrollment setup and verify non-targeted contexts remain.
- Attempt delete with ambiguous selector and verify deterministic no-op with guidance.

R065  Statement: Reconnect an existing enrollment from `06_capture_teller_token.sh`.
Design: Add reconnect mode that uses a selected `enrollment_id` in Teller Connect repair mode.
Constraints:

- Reconnect action MUST route through repair mode (`enrollment_id` set).
- Reconnect action MUST persist refreshed token/enrollment context for only the targeted enrollment.
Tests:
- Reconnect a disconnected enrollment and verify only the selected context changes.
- Reconnect one enrollment and verify unrelated enrollment files are unchanged.

R070  Statement: Add a new enrollment from `06_capture_teller_token.sh`.
Design: Add mode MUST run Teller Connect without repair enrollment id and persist resulting enrollment context.
Constraints:

- Add mode MUST disable automatic repair for that run.
- Add mode MUST open the Teller Connect web UI and let the user pick the institution there.
- Add mode MUST NOT require `--institution_id` as an input to start enrollment.
- Add mode MUST persist new enrollment using institution-specific context files to preserve existing defaults.
- Institution-specific suffix for persisted files SHOULD be derived from enrollment/identity data returned after Connect succeeds.
Tests:
- Run `./06_capture_teller_token.sh --add` and verify Connect UI opens for institution selection.
- Add a new `chase` enrollment with existing `first_ak_bank_trust` context and verify both contexts remain selectable.
- Verify add mode does not overwrite unrelated suffix contexts.

R075  Statement: Show existing enrollments in Connect UI when not in repair mode.
Design: When `06_capture_teller_token.sh` launches Connect without `enrollment_id`, the browser page lists known local enrollment
contexts before opening Teller Connect.
Constraints:

- Enrollment list MUST be read from local Teller context files only.
- List MUST include `institution_id` and `enrollment_id` when available.
- Missing context files MUST NOT fail the page; render an empty-state message instead.
Tests:
- Run `./06_capture_teller_token.sh --add` and verify the page shows known local enrollments before connecting.
- Run `./06_capture_teller_token.sh` with no local contexts and verify the page shows an explicit no-enrollments message.

R080  Statement: Manage enrollment actions directly from Connect UI.
Design: Default `06_capture_teller_token.sh` browser flow MUST provide per-enrollment reconnect and delete actions plus add-enrollment
action without requiring CLI selectors.
Constraints:
- Reconnect action MUST use the selected enrollment context and launch Teller Connect repair for that enrollment.
- Delete action MUST move only selected local context files to local Trash and MUST NOT call Teller server-side delete APIs.
- Add action MUST launch Teller Connect enrollment flow and persist a new context file pair without overwriting existing contexts.
- Enrollment list display MUST show user-facing `institution_id` values; internal fields (file source, enrollment id) MUST NOT be shown.
Tests:
- Run `./06_capture_teller_token.sh` and verify existing rows expose reconnect/delete controls.
- Reconnect one row from UI and verify only that row's context files are updated.
- Delete one row from UI and verify only that row's local files are moved to Trash.
- Add one enrollment from UI and verify a new suffix context is created.
- Verify UI list columns exclude `enrollment_id` and `source`.

## Acceptance Matrix

- `no flag` + default credential only -> default enrollment attempted and reported.
- `no flag` + auto-discovered contexts -> all discovered contexts are attempted and reported.
- `--institution_id chase` -> only Chase enrollment(s) attempted.
- `--institution_id first_ak_bank_trust` -> only First AK enrollment(s) attempted.
- `--institution_id unknown_bank` -> no enrollment attempts; deterministic message and success exit.
- Chase credit card account present -> transactions are fetched and persisted.
- `06_capture_teller_token.sh --list` -> all known local enrollment contexts are displayed.
- `06_capture_teller_token.sh --delete <selector>` -> only selected enrollment context is removed.
- `06_capture_teller_token.sh --reconnect <selector>` -> selected enrollment is repaired without affecting others.
- `06_capture_teller_token.sh --add` -> Connect UI opens, user picks institution in UI, new context is persisted, and existing contexts remain.
- `06_capture_teller_token.sh` (non-repair) -> Connect page displays known local enrollments before user starts Connect.
- `06_capture_teller_token.sh` (default) -> Connect page allows reconnect, delete, and add actions directly from listed enrollments.

## Migration Notes

- No mandatory metadata migration is required.
- `auth_token.json` remains default and sufficient for single-enrollment operation.
- Multi-enrollment behavior is unlocked by automatic discovery from fixed local Teller files.

## Changelog

- 2026-04-13: Initial requirements for multi-enrollment selection and Chase credit-card ingestion (Teller API phase).
- 2026-04-13: Revised mapping to institution filter + CLI-targeted enrollments + Teller-only Chase ingestion.
- 2026-04-13: Replaced enrollment-file CLI model with auto-discovery + institution-id targeting only.
- 2026-04-15: Added explicit `06_capture_teller_token.sh` enrollment-management requirements (list/delete/reconnect/add).
- 2026-04-15: Updated add-flow requirement so `--add` launches Connect UI institution selection (no required `--institution_id`).
- 2026-04-15: Added Connect-page requirement to display known local enrollments for non-repair runs.
- 2026-04-15: Added default browser management actions (reconnect/delete/add) for listed enrollments.
- 2026-04-15: Updated management UI requirements to show institution-only user-facing columns.