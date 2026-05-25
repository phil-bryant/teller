# Run Unit Tests Requirements

## Scope

Applies to `09_run_unit_tests.sh`.

R001  Statement: Run project unit test suites from the repository root.
Design: Resolve script directory and `cd` into it before invoking shell/Python/Swift test commands.
Tests:
- R001-T01: Run script from a different working directory and verify tests still execute.

R005  Statement: Prefer the project virtual environment when available.
Design: If `./teller-venv` exists, source `./teller-venv/bin/activate` before running tests.
Tests:
- R005-T01: Create `teller-venv` and verify the runner uses venv-provided Python dependencies.

R010  Statement: Execute all unittest modules under `tests/py`.
Design: Run `python3 -m unittest discover tests/py` so all `test*.py` files are included.
Tests:
- R010-T01: Add multiple `test_*.py` modules under `tests/py` and verify the runner discovers each module.

R015  Statement: Fail fast on unit test failures.
Design: Use strict shell settings so non-zero exit from unittest propagates to the caller.
Tests:
- R015-T01: Introduce a failing test and verify script exits non-zero.

R020  Statement: Execute Swift package tests under `macos-ui/`.
Design: Remove stale `./macos-ui/.build` cache before running `swift test --package-path ./macos-ui` when Swift tests are enabled.
Tests:
- R020-T01: With Swift tests enabled, verify `swift test --package-path ./macos-ui` is invoked.
- R020-T02: Pre-create stale Swift module cache tied to an old package path and verify the runner clears cache before test invocation.
- R020-T03: Disable Swift tests and verify runner skips Swift invocation.

R025  Statement: Execute SQL unit tests from `tests/sql`.
Design: When SQL tests are enabled, print a SQL-lane prep status line, resolve DB connection settings from `TELLER_DB_*` defaults and `1psa` fallback password lookup, verify `pgtap` is installed in the target database using non-interactive `psql`, then run each `*.sql` pgTAP test file in `tests/sql` with `pg_prove --dbname <db>` and fail fast on the first failure. Resolve `pg_prove` from `PATH` first and fall back to `~/perl5/bin/pg_prove`; if direct execution of user-local `pg_prove` fails, retry through Homebrew Perl.
Tests:
- R025-T01: With SQL tests enabled and `pgtap` extension missing, verify runner exits non-zero with actionable extension-install guidance.
- R025-T02: With SQL tests enabled and `tests/sql` populated, verify `pg_prove --dbname prod <test-file>` is invoked.
- R025-T03: With SQL tests enabled and `pg_prove` missing, verify runner exits non-zero with actionable install guidance.
- R025-T04: With SQL tests enabled and `~/perl5/bin/pg_prove` present but not on `PATH`, verify runner uses the user-local `pg_prove` binary.
- R025-T05: With SQL tests enabled and direct user-local `pg_prove` execution failing, verify runner retries with Homebrew Perl.
- R025-T06: With SQL tests enabled, verify runner prints a SQL prep status line before preflight checks.
- R025-T07: With SQL tests enabled and preflight DB query failing, verify runner exits non-zero with explicit database-query failure context.
- R025-T08: With SQL tests enabled and `TELLER_DB_PASSWORD` unset, verify runner falls back to `1psa` lookup for teller DB password.
- R025-T09: Disable SQL tests and verify runner skips SQL invocation.

R030  Statement: Do not chain other numbered verification scripts from this runner.
Design: `09_run_unit_tests.sh` must not invoke `./11_verify_macos_crash_test.sh`, reference `verify_macos_crash_test`, or define `RUN_MACOS_CRASH_REPORTER_SMOKE_TEST`. Run that verification as its own numbered entrypoint when needed.
Tests:
- R030-T01: Grep the script text and verify it contains no `verify_macos_crash_test` substring and no `CRASH_REPORTER_SMOKE` token.

R035  Statement: Refuse SQL unit-test execution when DB profile setup is missing.
Design: SQL preflight profile resolution must fail fast when no profile file is configured and surface setup guidance to copy `db-profiles-EXAMPLE.json` rather than silently defaulting to local DB coordinates.
Tests:
- R035-T01: With SQL tests enabled and no candidate profile file, verify runner exits non-zero with copy-guidance text.

## Changelog

- 2026-05-23: Added R035 to require explicit DB profile setup before SQL test preflight.
- 2026-05-12: Replaced opt-in crash-reporter lane with R030 isolation requirement; verification is standalone `11_verify_macos_crash_test.sh`.
- 2026-05-07: Added R030 for optional PLCrashReporter smoke lane (later removed; see 2026-05-12).
- 2026-04-26: Added R025 to run SQL unit tests from `tests/sql`.
- 2026-04-23: Added R020 to run Swift package tests from `./macos-ui`.
- 2026-04-23: Initial requirements for `09_run_unit_tests.sh`.
