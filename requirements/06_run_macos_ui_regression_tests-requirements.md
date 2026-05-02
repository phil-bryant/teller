# Run macOS UI Regression Tests Requirements

## Scope

Applies to `06_run_macos_ui_regression_tests.sh`.

R001  Statement: Run in strict shell mode and fail fast.
Design: Use `set -euo pipefail` in the script entrypoint.
Tests:
- Force a command failure and verify script exits non-zero.

R005  Statement: Execute from repository root regardless of caller directory.
Design: Resolve script directory and `cd` into it before running test commands.
Tests:
- Run script from a different working directory and verify package paths resolve correctly.

R010  Statement: Run snapshot regression tests when enabled.
Design: Execute `swift test --package-path ./macos-ui --filter ContentViewSnapshotTests` when `RUN_SNAPSHOT_TESTS=true`.
Tests:
- Set `RUN_SNAPSHOT_TESTS=true` and verify snapshot test invocation occurs.
- Set `RUN_SNAPSHOT_TESTS=false` and verify snapshot lane is skipped with informational output.

R015  Statement: Support explicit snapshot record mode.
Design: When `SNAPSHOT_RECORD=true`, run snapshot tests with `SNAPSHOT_RECORD=1`.
Tests:
- Set `SNAPSHOT_RECORD=true` and verify environment variable is propagated for snapshot update mode.

R020  Statement: Run XCUITest smoke suite when enabled and prerequisites are present.
Design: When `RUN_XCUITESTS=true`, validate project/tool availability and execute `xcodebuild test` against configured project/scheme/destination.
Tests:
- Set `RUN_XCUITESTS=true` and verify `xcodebuild test` invocation path executes.
- Point `XCUITEST_PROJECT` to a missing path and verify explicit non-zero failure.

R025  Statement: Support a snapshot-only gate for fast pre-merge feedback.
Design: Allow `RUN_SNAPSHOT_TESTS=true` with `RUN_XCUITESTS=false` so snapshot coverage runs while XCUITest smoke lane is explicitly skipped.
Tests:
- Set `RUN_SNAPSHOT_TESTS=true` and `RUN_XCUITESTS=false` and verify snapshot command runs while XCUITest skip message is emitted.

R030  Statement: Default to full UI regression coverage when no overrides are provided.
Design: Default both `RUN_SNAPSHOT_TESTS` and `RUN_XCUITESTS` to `true` so the baseline invocation runs snapshot and XCUITest smoke lanes.
Tests:
- Run with no lane overrides and verify both snapshot and `xcodebuild test` paths execute.

R035  Statement: Expose XCUITest runtime overrides for stable worker execution.
Design: Support environment overrides for `XCUITEST_PROJECT`, `XCUITEST_SCHEME`, `XCUITEST_DESTINATION`, and `XCUITEST_DERIVED_DATA_PATH`.
Tests:
- Set non-default destination and derived data path overrides and verify values are propagated into `xcodebuild test`.

R040  Statement: Allow selecting specific UI regression tests by numeric selector argument.
Design: Accept an optional positional selector argument with forms `N`, comma-separated lists (`N,M`), and ranges (`N-M`) mapped to an ordered list of known UI regression tests.
Tests:
- Run `06_run_macos_ui_regression_tests.sh 1,3,5-6` and verify only matching `-only-testing` entries are passed to `xcodebuild test`.

R045  Statement: Fail fast when selectors reference non-existent test numbers.
Design: Validate each parsed selector index against the known UI regression test list and exit non-zero with an explicit error before invoking `xcodebuild` when out of range.
Tests:
- Run `06_run_macos_ui_regression_tests.sh 99` and verify the script exits non-zero with an unknown-test-number error and does not call `xcodebuild`.

## Changelog

- 2026-04-24: Initial requirements for `06_run_macos_ui_regression_tests.sh`.
- 2026-04-24: Folded gate rollout guidance from `macos-ui/UI_REGRESSION_ROLLOUT.md` into script-scoped requirements.
- 2026-05-02: Added optional numeric XCUITest selectors and strict out-of-range validation requirements.
