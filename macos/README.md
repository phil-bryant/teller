# TellerReclassifier (macOS SwiftUI)

Native macOS UI for reclassifying `teller.transaction` records into `teller.nys_snw_category`.

## 1) Start API

From repo root:

```zsh
./09_transaction_reclassification_api.py
```

Defaults to `http://127.0.0.1:8787`. Override with:

- `TELLER_CLASSIFIER_API_HOST`
- `TELLER_CLASSIFIER_API_PORT`

## 2) Launch app

From `macos/`:

```zsh
swift run TellerReclassifier
```

Or open `macos/` directly in Xcode and run the executable target.

## 3) Keyboard shortcuts

- `Cmd+F` focus search
- `Cmd+]` jump to next unclassified transaction
- `Cmd+Return` apply selected category to all selected rows
- `Cmd+Z` undo last classification action (session-scoped)

## 4) Verification helpers

From repo root:

- `./10_run_reclassification_api_tests.py` (API unit tests)
- `TXN_ID=... CATEGORY_ID=... ./11_verify_reclassification_persistence.sh` (end-to-end persistence check)
