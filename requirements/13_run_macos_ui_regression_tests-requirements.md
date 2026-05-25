# Run macOS UI Regression Tests Requirements

## Scope

Applies to `13_run_macos_ui_regression_tests.sh`.

R001  Statement: Run in strict shell mode and fail fast.
Design: Use `set -euo pipefail` in the script entrypoint.
Tests:
- R001-T01: Force a command failure and verify script exits non-zero.

R005  Statement: Execute from repository root regardless of caller directory.
Design: Resolve script directory and `cd` into it before running test commands.
Tests:
- R005-T01: Run script from a different working directory and verify package paths resolve correctly.

R010  Statement: Run snapshot regression tests when enabled.
Design: Execute `swift test --package-path ./macos-ui --filter ContentViewSnapshotTests` when `RUN_SNAPSHOT_TESTS=true`.
Tests:
- R010-T01: Set `RUN_SNAPSHOT_TESTS=true` and verify snapshot test invocation occurs.
- R010-T02: Set `RUN_SNAPSHOT_TESTS=false` and verify snapshot lane is skipped with informational output.

R015  Statement: Support explicit snapshot record mode.
Design: When `SNAPSHOT_RECORD=true`, run snapshot tests with `SNAPSHOT_RECORD=1`.
Tests:
- R015-T01: Set `SNAPSHOT_RECORD=true` and verify environment variable is propagated for snapshot update mode.

R020  Statement: Run XCUITest smoke suite when enabled and prerequisites are present.
Design: When `RUN_XCUITESTS=true`, validate project/tool availability and execute `xcodebuild test` against configured project/scheme/destination.
Tests:
- R020-T01: Set `RUN_XCUITESTS=true` and verify `xcodebuild test` invocation path executes.
- R020-T02: Point `XCUITEST_PROJECT` to a missing path and verify explicit non-zero failure.

R025  Statement: Support a snapshot-only gate for fast pre-merge feedback.
Design: Allow `RUN_SNAPSHOT_TESTS=true` with `RUN_XCUITESTS=false` so snapshot coverage runs while XCUITest smoke lane is explicitly skipped.
Tests:
- R025-T01: Set `RUN_SNAPSHOT_TESTS=true` and `RUN_XCUITESTS=false` and verify snapshot command runs while XCUITest skip message is emitted.

R030  Statement: Default to full UI regression coverage when no overrides are provided.
Design: Default both `RUN_SNAPSHOT_TESTS` and `RUN_XCUITESTS` to `true` so the baseline invocation runs snapshot and XCUITest smoke lanes.
Tests:
- R030-T01: Run with no lane overrides and verify both snapshot and `xcodebuild test` paths execute.

R035  Statement: Expose XCUITest runtime overrides for stable worker execution.
Design: Support environment overrides for `XCUITEST_PROJECT`, `XCUITEST_SCHEME`, `XCUITEST_DESTINATION`, and `XCUITEST_DERIVED_DATA_PATH`.
Tests:
- R035-T01: Set non-default destination and derived data path overrides and verify values are propagated into `xcodebuild test`.

R040  Statement: Allow selecting specific smoke-suite scenario steps by numeric selector argument.
Design: Accept an optional positional selector argument with forms `N`, comma-separated lists (`N,M`), and ranges (`N-M`) mapped to an ordered list of known scenarios inside `testMacOSUISmokeSuite`. When selectors are provided, export `XCUITEST_STEPS` to the test runner and invoke a single `-only-testing:TransactionClassifierUITests/TransactionClassifierUITests/testMacOSUISmokeSuite` entry (one app launch per run).
Tests:
- R040-T01: Run `13_run_macos_ui_regression_tests.sh 1,3,5-6` and verify `XCUITEST_STEPS=1,3,5,6` is exported and only `testMacOSUISmokeSuite` is passed to `xcodebuild test`.

R045  Statement: Fail fast when selectors reference non-existent scenario numbers.
Design: Validate each parsed selector index against the known scenario list and exit non-zero with an explicit error before invoking `xcodebuild` when out of range.
Tests:
- R045-T01: Run `13_run_macos_ui_regression_tests.sh 99` and verify the script exits non-zero with an unknown-scenario-number error and does not call `xcodebuild`.

R050  Statement: Do not chain macOS crash-reporter verification from this UI regression runner.
Design: `13_run_macos_ui_regression_tests.sh` must not invoke `./14_verify_macos_crash_test.sh`, reference `verify_macos_crash_test`, or define `RUN_CRASH_REPORTER_SMOKE_TEST`. Run PLCrashReporter verification via `./14_verify_macos_crash_test.sh` as a separate step when needed.
Tests:
- R050-T01: Grep the script text and verify it contains no `verify_macos_crash_test` substring and no `CRASH_REPORTER_SMOKE` token.

## Changelog

- 2026-05-20: Reworked XCUITest lane to a single-session `testMacOSUISmokeSuite` with 12 requirement-driven scenarios; R040/R045 now target scenario-step selection via `XCUITEST_STEPS`.
- 2026-05-12: Replaced optional crash-reporter lane with R050 isolation requirement; verification is standalone `14_verify_macos_crash_test.sh`.
- 2026-04-24: Initial requirements for `13_run_macos_ui_regression_tests.sh`.
- 2026-04-24: Folded gate rollout guidance from `macos-ui/UI_REGRESSION_ROLLOUT.md` into script-scoped requirements.
- 2026-05-02: Added optional numeric XCUITest selectors and strict out-of-range validation requirements.
- 2026-05-07: Added optional PLCrashReporter smoke-verification lane (later removed; see 2026-05-12).
