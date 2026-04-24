# Run Transaction Classification macOS UI Requirements

## Scope

Applies to `15_run_transaction_classification_macos-ui.sh`.

R001  Statement: Run in strict shell mode and fail fast.
Design: Use `set -euo pipefail` to propagate execution failures.
Tests:
- Force `swift` command failure and verify script exits non-zero.

R005  Statement: Resolve repository root from script location.
Design: Compute repo root from the script path so package path does not depend on caller cwd.
Tests:
- Run script from another directory and verify `--package-path` points to repo `macos-ui`.

R010  Statement: Forward all CLI args to the SwiftUI app runner.
Design: Execute `swift run --package-path <repo>/macos-ui TransactionClassifier "$@"` without swallowing arguments.
Tests:
- Pass multiple args and verify they are forwarded in order to `swift run`.

## Changelog

- 2026-04-24: Initial requirements for `15_run_transaction_classification_macos-ui.sh`.
