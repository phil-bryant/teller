---
name: stabilize-t07-db-shell-tests
overview: Harden t07 shell unit tests against leaked DB profile environment and align assertions with recent DB script behavior changes so the shell lane is deterministic across local profiles.
todos:
  - id: runner-env-scrub
    content: Unset profile-sensitive DB env vars around all bats invocations in run_unit_test_lanes.sh
    status: completed
  - id: postgres-stub-defaults
    content: Add DB_DIALECT=postgresql to postgres-oriented profile stub fixtures in failing bats files
    status: completed
  - id: assertion-alignment
    content: Update stale bats assertions to match quoted schema and inline SQL behavior
    status: completed
  - id: script-hardening
    content: Unset profile env keys in DB scripts before sourcing profile resolver exports
    status: completed
  - id: verify-t07
    content: Run targeted bats files, then t07 shell lane, then full parallel suite
    status: in_progress
isProject: false
---

# Stabilize t07 DB Shell Tests

## Goal
Make `t07_run_shell_unit_tests.sh` pass consistently even when the active local DB profile is SQLite, while preserving recent PostgreSQL safety/script behavior changes.

## Findings To Address
- `run_unit_test_lanes` currently exports profile env (`set -a`) and leaks `DB_DIALECT=sqlite` into bats children, causing many PostgreSQL tests to execute SQLite branches.
- A few assertions in bats files are stale relative to recent script updates (quoted schema identifiers and inline SQL checks).

## Implementation Steps
- Update the bats invocation environment in [`/Users/phil/local/src/teller/src/scripts/run_unit_test_lanes.sh`](/Users/phil/local/src/teller/src/scripts/run_unit_test_lanes.sh) to explicitly unset profile-sensitive variables before each bats execution (both serial and parallel code paths), including `DB_DIALECT`, profile metadata, PG connection vars, and sqlite path vars.
- Add defensive `DB_DIALECT=postgresql` emission to PostgreSQL-oriented profile stubs in:
  - [`/Users/phil/local/src/teller/tests/sh/06_deploy_database.bats`](/Users/phil/local/src/teller/tests/sh/06_deploy_database.bats)
  - [`/Users/phil/local/src/teller/tests/sh/98_destroy_database.bats`](/Users/phil/local/src/teller/tests/sh/98_destroy_database.bats)
  - [`/Users/phil/local/src/teller/tests/sh/99_restore_database.bats`](/Users/phil/local/src/teller/tests/sh/99_restore_database.bats)
  - [`/Users/phil/local/src/teller/tests/sh/t05_deploy_database_verification_test.bats`](/Users/phil/local/src/teller/tests/sh/t05_deploy_database_verification_test.bats)
- Align outdated expectations with current script behavior:
  - In [`/Users/phil/local/src/teller/tests/sh/98_destroy_database.bats`](/Users/phil/local/src/teller/tests/sh/98_destroy_database.bats), accept quoted `DROP SCHEMA IF EXISTS "teller" CASCADE;`.
  - In [`/Users/phil/local/src/teller/tests/sh/99_restore_database.bats`](/Users/phil/local/src/teller/tests/sh/99_restore_database.bats), update scoped repair SQL assertions to match inline SQL checks (instead of psql `-v` variables).
  - In [`/Users/phil/local/src/teller/tests/sh/06_deploy_database.bats`](/Users/phil/local/src/teller/tests/sh/06_deploy_database.bats), update any remaining database-existence SQL matchers that still expect old placeholder syntax.
- Optional belt-and-suspenders hardening (included in this hardened scope): unset profile keys inside DB scripts before sourcing resolver exports in:
  - [`/Users/phil/local/src/teller/06_deploy_database.sh`](/Users/phil/local/src/teller/06_deploy_database.sh)
  - [`/Users/phil/local/src/teller/98_destroy_database.sh`](/Users/phil/local/src/teller/98_destroy_database.sh)
  - [`/Users/phil/local/src/teller/99_restore_database.sh`](/Users/phil/local/src/teller/99_restore_database.sh)
  - [`/Users/phil/local/src/teller/tests/t05_deploy_database_verification_test.sh`](/Users/phil/local/src/teller/tests/t05_deploy_database_verification_test.sh)

## Verification
- Run targeted bats files first to confirm deterministic behavior:
  - `tests/sh/06_deploy_database.bats`
  - `tests/sh/98_destroy_database.bats`
  - `tests/sh/99_restore_database.bats`
  - `tests/sh/t05_deploy_database_verification_test.bats`
- Run `tests/t07_run_shell_unit_tests.sh`.
- Re-run `./11_run_all_tests_parallel.sh` to confirm no regressions in other lanes.

## Expected Outcome
`t07` stops failing due to host profile leakage and stale assertions, with DB shell tests stable regardless of local `DB_DIALECT` defaults.