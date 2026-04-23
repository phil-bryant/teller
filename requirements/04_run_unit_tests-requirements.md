# Run Unit Tests Requirements

## Scope

Applies to `04_run_unit_tests.sh`.

R001  Statement: Run project unit test suites from the repository root.
Design: Resolve script directory and `cd` into it before invoking shell/Python/Swift test commands.
Tests:
- Run script from a different working directory and verify tests still execute.

R005  Statement: Prefer the project virtual environment when available.
Design: If `./teller-venv` exists, source `./teller-venv/bin/activate` before running tests.
Tests:
- Create `teller-venv` and verify the runner uses venv-provided Python dependencies.

R010  Statement: Execute all unittest modules under `tests/py`.
Design: Run `python3 -m unittest discover tests/py` so all `test*.py` files are included.
Tests:
- Add multiple `test_*.py` modules under `tests/py` and verify the runner discovers each module.

R015  Statement: Fail fast on unit test failures.
Design: Use strict shell settings so non-zero exit from unittest propagates to the caller.
Tests:
- Introduce a failing test and verify script exits non-zero.

R020  Statement: Execute Swift package tests under `macos/`.
Design: Run `swift test --package-path ./macos` when Swift tests are enabled.
Tests:
- With Swift tests enabled, verify `swift test --package-path ./macos` is invoked.
- Disable Swift tests and verify runner skips Swift invocation.

## Changelog

- 2026-04-23: Added R020 to run Swift package tests from `./macos`.
- 2026-04-23: Initial requirements for `04_run_unit_tests.sh`.
