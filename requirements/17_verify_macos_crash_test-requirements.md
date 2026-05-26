# Verify macOS Crash Reporter Requirements

## Scope

Applies to `tests/t15_verify_macos_crash_test.sh`.

## Ownership Boundaries

This document owns crash-verification flow behavior.
Shared SwiftPM lock helper implementation details are owned by:
- `requirements/src/scripts/macos_ui_swift_lock-requirements.md`

R001  Statement: Run in strict shell mode and fail fast.
Design: Use `set -euo pipefail` at script entry.
Tests:
- R001-T01: Force an inner command failure and verify non-zero exit.

R005  Statement: Execute from repository root regardless of caller directory.
Design: Resolve script directory and `cd` into it before running verification commands.
Tests:
- R005-T01: Run script from a different working directory and verify relative `./src/macos-ui` path resolves.

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
Design: This script is invoked directly (or from ad-hoc automation), not from other repository-numbered control-plane scripts such as `10_run_shell_unit_tests.sh` or `16_run_macos_ui_regression_tests.sh`. Those runners must not reference or execute crash-reporter verification.
Tests:
- R040-T01: Covered by static grep tests in `tests/sh/10_run_shell_unit_tests.bats` and `tests/sh/16_run_macos_ui_regression_tests.bats`.

R045  Statement: Recover once from stale SwiftPM checkout metadata during relaunch.
Design: When relaunch fails with missing `.build/checkouts/...` dependency paths, repair SwiftPM state with `rm -rf .build && swift package resolve` under the macOS UI lock and retry relaunch exactly once.
Tests:
- R045-T01: Simulate stale checkout error on first relaunch, ensure recovery path runs `swift package resolve`, and verify script succeeds on retry.

R050  Statement: Fail quickly when relaunch does not report crash persistence.
Design: Relaunch in the background and stop as soon as the persistence log appears; if the log is still absent at `STARTUP_WAIT_SECONDS`, terminate relaunch process tree and fail with timeout output.
Tests:
- R050-T01: Simulate relaunch with no persistence log and verify timeout failure is emitted without hanging.

R060  Statement: Prewarm the TransactionClassifier build before crash verification timing begins.
Design: Run a bounded `swift build --product TransactionClassifier` warm-up under the macOS UI SwiftPM lock before the forced-crash launch so relaunch timeout checks measure app startup behavior instead of cold dependency/build work.
Tests:
- R060-T01: Stub `swift` and verify the first invocation is `swift build --product TransactionClassifier` before forced-crash and relaunch runs.

R065  Statement: Verify unclean termination marker persistence on relaunch.
Design: Simulate a prior unclean exit by writing `session-active.json` in the crash-report directory, relaunch once, and require log output containing `CrashReporter: saved unclean termination marker to` plus a fresh `unclean-exit-*.json` artifact.
Tests:
- R065-T01: Stub relaunch output/artifacts for unclean-marker replay and verify script succeeds only when both marker log and fresh `unclean-exit-*.json` are observed.

## Changelog

- 2026-05-25: Added R065 to validate unclean-termination fallback marker replay.
- 2026-05-25: Added R060 requiring prewarm build before forced-crash/relaunch verification timing.
- 2026-05-25: Added R045/R050 for stale SwiftPM recovery and bounded relaunch timeout behavior.
- 2026-05-12: Added R040 documenting standalone use and forbidding chained invocation from `06_`/`07_` runners.
- 2026-05-07: Initial requirements for `17_verify_macos_crash_test.sh`.
