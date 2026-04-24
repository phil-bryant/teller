# TransactionClassifier (macOS SwiftUI)

Native macOS UI for reclassifying `teller.transaction` records into `teller.nys_snw_category`.

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

## 3) Keyboard shortcuts

- `Cmd+F` focus search
- `Cmd+]` jump to next unclassified transaction
- `Cmd+Return` apply selected category to all selected rows
- `Cmd+Z` undo last classification action (session-scoped)

## 4) Verification helpers

From repo root:

- `./04_run_unit_tests.sh` (API/unit tests)
- `./05_run_macos_ui_regression_tests.sh` (snapshot + macOS XCUITest smoke lane)
- `./16_verify_classification_persistence.sh` (auto-selects IDs for end-to-end persistence check)
- `TXN_ID=... CATEGORY_ID=... ./16_verify_classification_persistence.sh --require-env-ids` (strict CI mode)

## 5) Automated UI regression testing

Run from repo root:

```zsh
./05_run_macos_ui_regression_tests.sh
```

Available gates/flags:

- `RUN_SNAPSHOT_TESTS=true|false` (default `true`) to run only Swift snapshot regression coverage.
- `SNAPSHOT_RECORD=true|false` (default `false`) to refresh snapshot baselines intentionally.
- `RUN_XCUITESTS=true|false` (default `true`) to include/exclude macOS XCUITest smoke tests.
- `XCUITEST_PROJECT` (default `./macos-ui/TransactionClassifierUIAutomation.xcodeproj`)
- `XCUITEST_SCHEME` (default `TransactionClassifierUITestHost`)
- `XCUITEST_DERIVED_DATA_PATH` (default `./macos-ui/.derivedData-ui-tests`)

The UI regression script runs tests via `xcodebuild test` and should not require opening `*-Runner.app` manually in Finder.

Snapshot tests live in `Tests/TransactionClassifierSnapshotTests` and validate key UI states:

- empty/no selection
- loaded selection
- error banner
- mixed-category selection
- save-state indicators

XCUITest smoke tests live in `UITests/TransactionClassifierUITests.swift` and cover keyboard-first critical paths (`Cmd+]`, `Cmd+Z`), category apply flows, search filtering, and load-more behavior in deterministic fixture mode.

Rollout guidance and gating order are documented in `UI_REGRESSION_ROLLOUT.md`.
