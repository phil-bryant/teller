# Verify macOS Crash Reporter Requirements

## Scope

Applies to `11_verify_macos_crash_test.sh`.

R001  Statement: Run in strict shell mode and fail fast.
Design: Use `set -euo pipefail` at script entry.
Tests:
- R001-T01: Force an inner command failure and verify non-zero exit.

R005  Statement: Execute from repository root regardless of caller directory.
Design: Resolve script directory and `cd` into it before running verification commands.
Tests:
- R005-T01: Run script from a different working directory and verify relative `./macos-ui` path resolves.

R010  Statement: Confirm forced crash path exits non-zero.
Design: Invoke `swift run TransactionClassifier` with `TELLER_MACOS_FORCE_CRASH_ON_LAUNCH=1` and fail if it exits zero.
Tests:
- R010-T01: Stub forced-crash launch to exit zero and verify script fails with expectation message.

R015  Statement: Confirm relaunch persists pending crash report.
Design: Relaunch app after forced crash and require log output containing `CrashReporter: saved pending crash report to`.
Tests:
- R015-T01: Simulate second launch output with expected persistence log and verify step passes.
- R015-T02: Simulate missing persistence log and verify script exits non-zero.

R020  Statement: Verify crash and metadata artifacts were written in current run.
Design: Require both `.plcrash` and `.json` files under configured crash-report directory and ensure newest files are newer than the run marker.
Tests:
- R020-T01: Simulate relaunch that writes both files and verify script succeeds.
- R020-T02: Simulate missing/old files and verify script exits non-zero.

R030  Statement: Fail clearly when local tooling/prerequisites are missing.
Design: Require `swift` command availability and existing `MACOS_UI_DIR` path before verification steps.
Tests:
- R030-T01: Run without `swift` on `PATH` and verify actionable failure.
- R030-T02: Point `MACOS_UI_DIR` to a missing path and verify explicit non-zero failure.

R035  Statement: Print concise success output with artifact paths.
Design: On success, emit `✅` status plus resolved paths for `.plcrash` and `.json` outputs.
Tests:
- R035-T01: Verify success output includes both artifact path lines.

R040  Statement: Remain a standalone numbered entrypoint.
Design: This script is invoked directly (or from ad-hoc automation), not from other repository-numbered control-plane scripts such as `09_run_unit_tests.sh` or `10_run_macos_ui_regression_tests.sh`. Those runners must not reference or execute crash-reporter verification.
Tests:
- R040-T01: Covered by static grep tests in `tests/sh/09_run_unit_tests.bats` and `tests/sh/10_run_macos_ui_regression_tests.bats`.

## Changelog

- 2026-05-12: Added R040 documenting standalone use and forbidding chained invocation from `05_`/`06_` runners.
- 2026-05-07: Initial requirements for `11_verify_macos_crash_test.sh`.
