# Run Dependency Freshness Checks Requirements

## Scope

Applies to `04_run_dependency_freshness_checks.sh`.

R001  Statement: Run from repository root regardless of caller working directory.
Design: Resolve script directory from `${BASH_SOURCE[0]}` and `cd` into it before invoking local scripts.
Tests:
- R001-T01: Run from a non-root directory and verify report paths resolve under repo root.

R005  Statement: Select the project interpreter predictably.
Design: Prefer `${VIRTUAL_ENV}/bin/python` when active, else `./teller-venv/bin/python`, else `python3`; fail fast when explicit interpreter path is not executable.
Tests:
- R005-T01: Run with active virtualenv and verify selected interpreter path is printed.
- R005-T02: Set `DEPENDENCY_CHECK_PYTHON` to a bad path and verify script exits non-zero.

R010  Statement: Produce dependency freshness artifacts and fail when direct requirements are stale.
Design: Execute `scripts/check_dependency_freshness.py` and always write `dependency-freshness.json` and `dependency-freshness.txt` to resolved report directory; pass `--fail-on-direct-outdated` by default (unless `DEPENDENCY_FAIL_ON_DIRECT_OUTDATED=false`) and pass `--fail-on-major` when `DEPENDENCY_FAIL_ON_MAJOR=true`.
Tests:
- R010-T01: Run default lane and verify both freshness artifacts are generated.
- R010-T02: Verify default invocation includes direct-requirements failure gating.
- R010-T03: Set `DEPENDENCY_FAIL_ON_DIRECT_OUTDATED=false` and verify direct-requirements failure gating is omitted.
- R010-T04: Enable `DEPENDENCY_FAIL_ON_MAJOR=true` and verify major-update failure gating is enabled.

R015  Statement: Support optional Teller API drift canary checks.
Design: Execute `scripts/check_teller_api_drift.py` only when `RUN_TELLER_CANARY=true` and write drift artifacts to report directory.
Tests:
- R015-T01: Run with `RUN_TELLER_CANARY=false` and verify drift script is skipped.
- R015-T02: Run with `RUN_TELLER_CANARY=true` and verify drift artifacts are generated.

R020  Statement: Support optional PostgreSQL version freshness checks.
Design: Execute `scripts/check_postgres_freshness.py` only when `RUN_POSTGRES_FRESHNESS=true`, always write `postgres-freshness.json` and `postgres-freshness.txt`, and pass configured minimum versions / gating flags through environment-backed options.
Tests:
- R020-T01: Run default lane and verify PostgreSQL freshness artifacts are generated.
- R020-T02: Run with `RUN_POSTGRES_FRESHNESS=false` and verify PostgreSQL freshness script is skipped.

R025  Statement: Evaluate PostgreSQL freshness against local CVE policy/snapshot data.
Design: Default `04_run_dependency_freshness_checks.sh` behavior passes CVE evaluation flags and repository policy/snapshot paths to `scripts/check_postgres_freshness.py`, refreshes snapshot data from PostgreSQL security advisories, and evaluates both client/server versions. Snapshot refresh writes `postgres-cve-snapshot.json` only when advisory payload content changes (not when only `generated_at` changes). Support disabling CVE checks via `RUN_POSTGRES_FRESHNESS` or `POSTGRES_CHECK_CVES=false`.
Tests:
- R025-T01: Run default lane and verify CVE policy/snapshot flags are passed to PostgreSQL freshness script.
- R025-T02: Run with `POSTGRES_CHECK_CVES=false` and verify CVE flags are not passed.
- R025-T03: Refresh snapshot data where only `generated_at` changes and verify snapshot file is not rewritten.

## Changelog

- 2026-04-26: Initial requirements for `04_run_dependency_freshness_checks.sh`.
- 2026-04-26: Added optional PostgreSQL freshness requirements and test coverage.
- 2026-04-26: Added CVE policy/snapshot integration requirements for PostgreSQL freshness checks.
- 2026-05-12: Updated R010 to fail by default when direct `requirements.txt` entries are outdated.
- 2026-05-12: Updated R025 snapshot refresh behavior to avoid rewrites when only `generated_at` changes.
