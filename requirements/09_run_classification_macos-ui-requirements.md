# Run Transaction Classification macOS UI Requirements

## Scope

Applies to `09_run_classification_macos_ui.sh`.

R001  Statement: Run in strict shell mode and fail fast.
Design: Use `set -euo pipefail` to propagate execution failures.
Tests:
- R001-T01: Force `swift build` failure and verify script exits non-zero.

R005  Statement: Resolve repository root from script location.
Design: Compute repo root from the script path so package path does not depend on caller cwd.
Tests:
- R005-T01: Run script from another directory and verify `swift build` uses repo `src/macos-ui` via `--package-path`.

R010  Statement: Build and launch the TransactionClassifier binary with forwarded CLI args.
Design: Run `swift build --package-path <repo>/src/macos-ui -c debug --product TransactionClassifier`, then launch `.build/debug/TransactionClassifier` in the background with any non-launcher args appended. When no extra args are provided, launch the binary without expanding an empty array (safe under `set -u`).
Tests:
- R010-T01: Verify the script references `swift build`, the debug binary path, and conditional `app_args` forwarding.
- R010-T02: Verify launching with only `--profile` does not fail on empty `app_args` under `set -u`.

R015  Statement: Optional transaction-list profiling via `--profile`.
Design: When `--profile` is passed, export `TELLER_UI_PROFILE_TRANSACTION_LIST=true` for the app process and print a one-line notice to stderr. Strip `--profile` before forwarding remaining args to the binary. Document usage in `--help`.
Tests:
- R015-T01: Verify `--profile` sets `TELLER_UI_PROFILE_TRANSACTION_LIST` in the launch environment.
- R015-T02: Verify `--help` documents `--profile`.

## Changelog

- 2026-04-24: Initial requirements for `09_run_classification_macos_ui.sh`.
- 2026-05-26: Updated R010 for binary launch + empty-arg safety; added R015 (`--profile`).
- 2026-05-26: Replaced deprecated `23` wrapper requirements with canonical `24` launcher requirements.
# Run Transaction Classification macOS UI Requirements

## Scope

Applies to `09_run_classification_macos_ui.sh`.

R001  Statement: Run in strict shell mode and fail fast.
Design: Use `set -euo pipefail` to propagate execution failures.
Tests:
- R001-T01: Force `swift build` failure and verify script exits non-zero.

R005  Statement: Resolve repository root from script location.
Design: Compute repo root from the script path so package path does not depend on caller cwd.
Tests:
- R005-T01: Run script from another directory and verify `swift build` uses repo `src/macos-ui` via `--package-path`.

R010  Statement: Build and launch the TransactionClassifier binary with forwarded CLI args.
Design: Run `swift build --package-path <repo>/src/macos-ui -c debug --product TransactionClassifier`, then launch `.build/debug/TransactionClassifier` in the background with any non-launcher args appended. When no extra args are provided, launch the binary without expanding an empty array (safe under `set -u`).
Tests:
- R010-T01: Verify the script references `swift build`, the debug binary path, and conditional `app_args` forwarding.
- R010-T02: Verify launching with only `--profile` does not fail on empty `app_args` under `set -u`.

R015  Statement: Optional transaction-list profiling via `--profile`.
Design: When `--profile` is passed, export `TELLER_UI_PROFILE_TRANSACTION_LIST=true` for the app process and print a one-line notice to stderr. Strip `--profile` before forwarding remaining args to the binary. Document usage in `--help`.
Tests:
- R015-T01: Verify `--profile` sets `TELLER_UI_PROFILE_TRANSACTION_LIST` in the launch environment.
- R015-T02: Verify `--help` documents `--profile`.

## Changelog

- 2026-04-24: Initial requirements for `09_run_classification_macos_ui.sh`.
- 2026-05-26: Updated R010 for binary launch + empty-arg safety; added R015 (`--profile`).
- 2026-05-26: Replaced deprecated `23` wrapper requirements with canonical `24` launcher requirements.
# macOS UI Launcher Requirements

## Scope

Applies to `09_run_classification_macos_ui.sh`.

R001  Statement: Run in strict shell mode and fail fast.
Design: Use `set -euo pipefail` so argument parsing and launcher setup fail safely.
Tests:
- R001-T01: Verify the launcher sets `set -euo pipefail`.

R005  Statement: Resolve repository root from the launcher location.
Design: Compute `repo_root` from `${BASH_SOURCE[0]}` and derive `src/macos-ui` relative paths from it.
Tests:
- R005-T01: Verify the launcher computes `repo_root` from `${BASH_SOURCE[0]}`.

R010  Statement: Build the TransactionClassifier product before launch.
Design: Invoke `swift build` for `TransactionClassifier` with in-process connect environment variables and fail on build errors.
Tests:
- R010-T01: Verify the launcher contains `swift build --package-path ... --product TransactionClassifier`.
- R010-T02: Verify launch logic supports empty `app_args` safely under `set -u`.

R015  Statement: Support optional profiling and pass through other arguments.
Design: Recognize `--profile` to set `TELLER_UI_PROFILE_TRANSACTION_LIST=true`, print profile guidance, and forward remaining arguments to TransactionClassifier.
Tests:
- R015-T01: Verify the launcher sets `TELLER_UI_PROFILE_TRANSACTION_LIST=true` when profiling is enabled.
- R015-T02: Verify the launcher advertises the `--profile` option in help output text.

## Changelog

- 2026-05-26: Replaced deprecated `23` wrapper requirements with canonical `24` launcher requirements.
# Run Transaction Classification macOS UI Requirements

## Scope

Applies to `09_run_classification_macos_ui.sh`.

R001  Statement: Run in strict shell mode and fail fast.
Design: Use `set -euo pipefail` to propagate execution failures.
Tests:
- R001-T01: Force `swift build` failure and verify script exits non-zero.

R005  Statement: Resolve repository root from script location.
Design: Compute repo root from the script path so package path does not depend on caller cwd.
Tests:
- R005-T01: Run script from another directory and verify `swift build` uses repo `src/macos-ui` via `--package-path`.

R010  Statement: Build and launch the TransactionClassifier binary with forwarded CLI args.
Design: Run `swift build --package-path <repo>/src/macos-ui -c debug --product TransactionClassifier`, then launch `.build/debug/TransactionClassifier` in the background with any non-launcher args appended. When no extra args are provided, launch the binary without expanding an empty array (safe under `set -u`).
Tests:
- R010-T01: Verify the script references `swift build`, the debug binary path, and conditional `app_args` forwarding.
- R010-T02: Verify launching with only `--profile` does not fail on empty `app_args` under `set -u`.

R015  Statement: Optional transaction-list profiling via `--profile`.
Design: When `--profile` is passed, export `TELLER_UI_PROFILE_TRANSACTION_LIST=true` for the app process and print a one-line notice to stderr. Strip `--profile` before forwarding remaining args to the binary. Document usage in `--help`.
Tests:
- R015-T01: Verify `--profile` sets `TELLER_UI_PROFILE_TRANSACTION_LIST` in the launch environment.
- R015-T02: Verify `--help` documents `--profile`.

## Changelog

- 2026-04-24: Initial requirements for `09_run_classification_macos_ui.sh`.
- 2026-05-26: Updated R010 for binary launch + empty-arg safety; added R015 (`--profile`).
