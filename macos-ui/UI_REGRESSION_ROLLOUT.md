# macOS UI Regression Rollout

Use this rollout to keep feedback fast while increasing coverage.

## Gate definitions

- **Gate 1 (`swift test`)**: existing unit tests and model logic.
- **Gate 2 (snapshot lane)**: `./15_run_macos_ui_regression_tests.sh` with `RUN_XCUITESTS=false`.
- **Gate 3 (full UI lane)**: `./15_run_macos_ui_regression_tests.sh` with defaults to include XCUITest smoke coverage.

## Suggested adoption order

1. Keep Gate 1 required for every change.
2. Enable Gate 2 in regular local pre-merge checks.
3. Enable Gate 3 on macOS workers once Xcode environment is stable and `xcodebuild` can run UI tests reliably.
4. Expand smoke test coverage only after first week of stable, low-flake runs.

## Operational flags

- `RUN_SNAPSHOT_TESTS=true|false`
- `SNAPSHOT_RECORD=true|false`
- `RUN_XCUITESTS=true|false`
- `XCUITEST_PROJECT` and `XCUITEST_SCHEME` for custom project/scheme overrides
