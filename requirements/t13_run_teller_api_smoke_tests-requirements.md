# Run Teller API Smoke Checks Requirements

## Scope

Applies to `tests/t13_run_teller_api_smoke_tests.sh`.

## Ownership Boundaries

This document owns wrapper orchestration behavior.
Smoke-check implementation details are owned by:
- `requirements/src/scripts/check_teller_api_drift-requirements.md`

R001  Statement: Run from repository root regardless of caller working directory.
Design: Resolve script directory from `${BASH_SOURCE[0]}` and `cd` into it before invoking local scripts.
Tests:
- R001-T01: Run from a non-root directory and verify report paths resolve under repo root.

R005  Statement: Select the project interpreter predictably.
Design: Prefer `${VIRTUAL_ENV}/bin/python` when active, else `./teller-venv/bin/python`, else `python3`; fail fast when explicit interpreter path is not executable.
Tests:
- R005-T01: Run with active virtualenv and verify selected interpreter path is printed.
- R005-T02: Set `DEPENDENCY_CHECK_PYTHON` to a bad path and verify script exits non-zero.

R010  Statement: Run Teller API smoke checks and emit artifacts.
Design: Execute `src/scripts/check_teller_api_drift.py` and always write `teller-api-smoke.json` and `teller-api-smoke.txt` to the resolved report directory.
Design: Use local token discovery by default (`~/.teller/auth_token*.json`) and run authenticated smoke checks (`/accounts`, `/identity`) across all discovered token contexts. Allow `TELLER_ACCESS_TOKEN` as an explicit single-token override/disambiguation path.
Tests:
- R010-T01: Run default lane and verify both smoke artifacts are generated.
- R010-T02: Set `TELLER_SMOKE_INSTITUTION_ID` and verify `--institution-id` is passed through.

## Changelog

- 2026-05-24: Initial requirements for `tests/t13_run_teller_api_smoke_tests.sh`.
