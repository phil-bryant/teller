# Run macOS UI Regression Tests Requirements

## Scope

Applies to `05_run_macos_ui_regression_tests.sh`.

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

## Changelog

- 2026-04-24: Initial requirements for `05_run_macos_ui_regression_tests.sh`.
