# TransactionClassifier (macOS SwiftUI)

Native macOS UI for reclassifying `teller.transaction` records into `teller.nys_snw_category`.

This app now also includes a native **Connect** tab for local Teller enrollment management (capture, reconnect, add, delete, and manual token save flows backed by the local connect token server).

## 1) Start API

From repo root:

```zsh
./14_run_classification_api.py
```

Defaults to `http://127.0.0.1:8787`. Override with:

- `TELLER_CLASSIFIER_API_HOST`
- `TELLER_CLASSIFIER_API_PORT`

## 2) Launch app

From `macos-ui/`:

```zsh
swift run TransactionClassifier
```

Or open `macos-ui/` directly in Xcode and run the executable target.

To open directly on the Connect tab:

```zsh
TELLER_MACOS_START_TAB=connect swift run TransactionClassifier
```

## Connect integration settings

Connect is now owned in-process by the app (local file-backed service + native WebView flow).

- `CONNECT_ENVIRONMENT` - Teller Connect environment passed into native Connect setup (default `development`).

From repo root, the recommended launcher is:

```zsh
./17_run_classification_macos-ui.sh
```

That command launches this macOS app; open the Connect tab to manage local enrollments.

## Crash reporting (PLCrashReporter)

The app now initializes `PLCrashReporter` on startup. If a prior run crashed, the next launch will persist the binary crash payload and metadata under:

- `~/Library/Application Support/<bundle-id>/CrashReports/*.plcrash`
- `~/Library/Application Support/<bundle-id>/CrashReports/*.json`

The `.plcrash` file is suitable for downstream symbolication/hand-off; the `.json` file stores minimal routing metadata (`bundle_id`, `version`, `build`, `captured_at`, `format`).

### Local verification

1. Launch once with an intentional crash toggle:

```zsh
TELLER_MACOS_FORCE_CRASH_ON_LAUNCH=1 swift run TransactionClassifier
```

2. Launch again normally:

```zsh
swift run TransactionClassifier
```

On the second launch, the app should detect and persist the pending crash report, then purge pending state.

## 3) Keyboard shortcuts

- `Cmd+F` focus search
- `Cmd+]` jump to next unclassified transaction
- `Cmd+Return` apply selected category to all selected rows
- `Cmd+Z` undo last classification action (session-scoped)

## 4) Verification helpers

From repo root:

- `./09_run_unit_tests.sh` (API/unit tests)
- `./10_run_macos_ui_regression_tests.sh` (snapshot + macOS XCUITest smoke lane)
- `./05_run_av_checks.sh` (standalone ClamAV antivirus lane)
- `./15_verify_classification_persistence.sh` (auto-selects IDs for end-to-end persistence check)
- `TXN_ID=... CATEGORY_ID=... ./15_verify_classification_persistence.sh --require-env-ids` (strict CI mode)

## 5) Automated UI regression testing

Run from repo root:

```zsh
./10_run_macos_ui_regression_tests.sh
```

Available gates/flags:

- `RUN_SNAPSHOT_TESTS=true|false` (default `true`) to run only Swift snapshot regression coverage.
- `SNAPSHOT_RECORD=true|false` (default `false`) to refresh snapshot baselines intentionally.
- `RUN_XCUITESTS=true|false` (default `true`) to include/exclude macOS XCUITest smoke tests.
- `XCUITEST_PROJECT` (default `./macos-ui/TransactionClassifierUIAutomation.xcodeproj`)
- `XCUITEST_SCHEME` (default `TransactionClassifierUITestHost-CI`)
- `XCUITEST_DERIVED_DATA_PATH` (default `./macos-ui/.derivedData-ui-tests`)

The UI regression script runs tests via `xcodebuild test` and should not require opening `*-Runner.app` manually in Finder.

Snapshot tests live in `Tests/TransactionClassifierSnapshotTests` and validate key UI states:

- empty/no selection
- loaded selection
- error banner
- mixed-category selection
- save-state indicators

XCUITest smoke tests live in `UITests/TransactionClassifierUITests.swift` as a **single-session** suite (`testMacOSUISmokeSuite`): one app launch, 12 ordered requirement-driven scenarios (Match & Classify shell, search, unclassified filter, classification/undo, scroll-into-view, Help menu, Connect tab), then one teardown. Optional positional selectors (e.g. `./10_run_macos_ui_regression_tests.sh 3,6`) set `XCUITEST_STEPS` to run a subset within the same session.

Rollout guidance and gating behavior are captured in `../requirements/10_run_macos_ui_regression_tests-requirements.md`.
