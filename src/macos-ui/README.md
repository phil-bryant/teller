# TransactionClassifier (macOS SwiftUI)

Native macOS UI for reclassifying `teller.transaction` records into `teller.nys_snw_category`.

This app now also includes a native **Connect** tab for local Teller enrollment management (capture, reconnect, add, delete) backed by an in-process file service (`~/.teller`) and native WebView flow.

## 1) Start API

From repo root:

```zsh
./05_install_classifier_api_tls.sh   # first run only (local HTTPS cert/key)
./09_run_classification_api.py
```

Defaults to **HTTPS** on `127.0.0.1:8787` using `~/.teller/classifier-localhost-cert.pem` and `~/.teller/classifier-localhost-key.pem`.

Override with:

- `TELLER_CLASSIFIER_API_HOST`
- `TELLER_CLASSIFIER_API_PORT`
- `TELLER_CLASSIFIER_TLS_CERT_FILE` / `TELLER_CLASSIFIER_TLS_KEY_FILE`
- `TELLER_CLASSIFIER_API_URL` (macOS API client; defaults to `https://127.0.0.1:8787` and must use `https://`)

Write operations require `1psa` item `TELLER_CLASSIFIER_WRITE_TOKEN` to be resolvable (used by the API launcher and mutation endpoints).

### Troubleshooting slow or failed loads

- **Spinner then error:** Confirm the API is listening on `https://127.0.0.1:8787`. Run `./05_install_classifier_api_tls.sh` if cert files are missing.
- **Still slow with API up:** Initial load skips the expensive `COUNT(*)` query and refreshes the total in the background; very large databases may still take time on first paint. Check PostgreSQL profile latency (`TELLER_DB_PROFILE`, managed vs local).
- **Proxy:** Unset `TELLER_CLASSIFIER_HTTP_PROXY` outside DAST/security test runs so loopback traffic is not proxied.

## 2) Launch app

From `src/macos-ui/`:

```zsh
swift run TransactionClassifier
```

Or open `src/macos-ui/` directly in Xcode and run the executable target.

To open directly on the Connect tab:

```zsh
TELLER_MACOS_START_TAB=connect swift run TransactionClassifier
```

## Connect integration settings

Connect is now owned in-process by the app (local file-backed service + native WebView flow).

- `CONNECT_ENVIRONMENT` - Teller Connect environment passed into native Connect setup (default `development`).

From repo root, the recommended launcher is:

```zsh
./10_run_classification_macos_ui.sh
```

Profile transaction-list load and first-render timings:

```zsh
./10_run_classification_macos_ui.sh --profile
```

That command launches this macOS app; open the Connect tab to manage local enrollments.

## Crash reporting (PLCrashReporter)

The app now initializes `PLCrashReporter` on startup. If a prior run crashed, the next launch will persist the binary crash payload and metadata under:

- `~/Library/Application Support/<bundle-id>/CrashReports/*.plcrash`
- `~/Library/Application Support/<bundle-id>/CrashReports/*.json`

The `.plcrash` file is suitable for downstream symbolication/hand-off; the `.json` file stores minimal routing metadata (`bundle_id`, `version`, `build`, `captured_at`, `format`).

When the app exits ungracefully (for example Force Quit or a kill while hung), PLCrashReporter may not emit a `.plcrash` file. To keep that path observable, the app now writes an `unclean-exit-*.json` marker on next launch when it detects the previous session did not terminate cleanly.

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

- `Cmd+]` jump to next unclassified transaction
- `Cmd+Return` apply selected category to all selected rows
- `Cmd+Z` undo last classification action (session-scoped)
- `Cmd+S` save category in Manage Categories tab

## 4) Verification helpers

From repo root:

- `./09_run_shell_unit_tests.sh` (API/unit tests)
- `./tests/t14_run_macos_ui_regression_tests.sh` (snapshot + macOS XCUITest smoke lane)
- `./tests/t01_run_av_test.sh` (standalone ClamAV antivirus lane)
- `./tests/t16_classification_persistence_verification_test.sh` (auto-selects IDs for end-to-end persistence check)
- `TXN_ID=... CATEGORY_ID=... ./tests/t16_classification_persistence_verification_test.sh --require-env-ids` (strict CI mode)

## 5) Automated UI regression testing

Run from repo root:

```zsh
./tests/t14_run_macos_ui_regression_tests.sh
```

Available gates/flags:

- `RUN_SNAPSHOT_TESTS=true|false` (default `true`) to run only Swift snapshot regression coverage.
- `SNAPSHOT_RECORD=true|false` (default `false`) to refresh snapshot baselines intentionally.
- `RUN_XCUITESTS=true|false` (default `true`) to include/exclude macOS XCUITest smoke tests.
- `XCUITEST_PROJECT` (default `./src/macos-ui/TransactionClassifierUIAutomation.xcodeproj`)
- `XCUITEST_SCHEME` (default `TransactionClassifierUITestHost-CI`)
- `XCUITEST_DERIVED_DATA_PATH` (default `./src/macos-ui/.derivedData-ui-tests`)

The UI regression script runs tests via `xcodebuild test` and should not require opening `*-Runner.app` manually in Finder.

Snapshot tests live in `Tests/TransactionClassifierSnapshotTests` and validate key UI states:

- empty/no selection
- loaded selection
- error banner
- mixed-category selection
- save-state indicators
- Connect tab (ready + error states)

XCUITest smoke tests live in `UITests/TransactionClassifierUITests.swift` as a **single-session** suite (`testMacOSUISmokeSuite`): one app launch, 12 ordered requirement-driven scenarios (Match & Classify shell, search, unclassified filter, classification/undo, scroll-into-view, Help menu, Connect tab), then one teardown. Optional positional selectors (e.g. `./tests/t14_run_macos_ui_regression_tests.sh 3,6`) set `XCUITEST_STEPS` to run a subset within the same session.

Rollout guidance and gating behavior are captured in `../../requirements/15_run_macos_ui_regression_tests-requirements.md`.
