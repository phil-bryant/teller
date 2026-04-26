# Run Dependency Freshness Checks Requirements

## Scope

Applies to `04_run_dependency_freshness_checks.sh`.

R001  Statement: Run from repository root regardless of caller working directory.
Design: Resolve script directory from `${BASH_SOURCE[0]}` and `cd` into it before invoking local scripts.
Tests:
- Run from a non-root directory and verify report paths resolve under repo root.

R005  Statement: Select the project interpreter predictably.
Design: Prefer `${VIRTUAL_ENV}/bin/python` when active, else `./teller-venv/bin/python`, else `python3`; fail fast when explicit interpreter path is not executable.
Tests:
- Run with active virtualenv and verify selected interpreter path is printed.
- Set `DEPENDENCY_CHECK_PYTHON` to a bad path and verify script exits non-zero.

R010  Statement: Produce dependency freshness artifacts with optional major-update gating.
Design: Execute `scripts/check_dependency_freshness.py` and always write `dependency-freshness.json` and `dependency-freshness.txt` to resolved report directory; pass `--fail-on-major` when `DEPENDENCY_FAIL_ON_MAJOR=true`.
Tests:
- Run default lane and verify both freshness artifacts are generated.
- Enable `DEPENDENCY_FAIL_ON_MAJOR=true` and verify non-zero exit when major upgrades exist.

R015  Statement: Support optional Teller API drift canary checks.
Design: Execute `scripts/check_teller_api_drift.py` only when `RUN_TELLER_CANARY=true` and write drift artifacts to report directory.
Tests:
- Run with `RUN_TELLER_CANARY=false` and verify drift script is skipped.
- Run with `RUN_TELLER_CANARY=true` and verify drift artifacts are generated.

## Changelog

- 2026-04-26: Initial requirements for `04_run_dependency_freshness_checks.sh`.
