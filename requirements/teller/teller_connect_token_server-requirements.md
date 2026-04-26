# Multi Enrollment UI Requirements

## Scope

Applies to `teller/teller_connect_token_server.py`.

## Requirements

R075  Statement: Show existing enrollments in Connect UI when not in repair mode.
Design: When Connect launches without a repair enrollment id, render known local enrollment contexts before opening Connect.
Constraints:
- Enrollment list MUST be read from local Teller context files only.
- List MUST include `institution_id` and `enrollment_id` when available.
- Missing context files MUST NOT fail the page; render an explicit empty-state message instead.
Tests:
- Run `./11_run_teller-connect-ui.sh --add` and verify the page shows known local enrollments before connecting.
- Run `./11_run_teller-connect-ui.sh` with no local contexts and verify the page shows a no-enrollments message.

R080  Statement: Manage enrollment actions directly from Connect UI.
Design: Management mode provides reconnect, delete, and add actions without requiring CLI selectors.
Constraints:
- Reconnect action MUST use selected enrollment context and launch Connect repair for that enrollment.
- Delete action MUST move only selected local context files to local Trash and MUST NOT call server-side delete APIs.
- Add action MUST launch Connect enrollment flow and persist a new context file pair without overwriting existing contexts.
- Enrollment list display MUST show user-facing `institution_id`; internal source fields MUST NOT be shown.
Tests:
- Run `./11_run_teller-connect-ui.sh` and verify existing rows expose reconnect/delete controls.
- Reconnect one row from UI and verify only that row's context files are updated.
- Delete one row from UI and verify only that row's local files are moved to Trash.
- Add one enrollment from UI and verify a new suffix context is created.

## Acceptance Matrix

- Non-repair launch shows existing local enrollment contexts before user starts Connect.
- Management UI exposes reconnect, delete, and add actions for listed enrollment contexts.
- Reconnect updates only selected enrollment context files.
- Delete moves only selected context files to local Trash.
- Add creates a new context without overwriting existing contexts.

## Changelog

- 2026-04-13: Initial multi-enrollment requirements document.
- 2026-04-20: Reduced scope to `teller/teller_connect_token_server.py`; moved ingestion and CLI-management requirements to file-specific docs.
