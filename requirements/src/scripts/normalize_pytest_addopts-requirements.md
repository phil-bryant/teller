# Normalize Pytest Addopts Requirements

## Scope

Applies to `src/scripts/normalize_pytest_addopts.sh`.

R001  Statement: Leave `PYTEST_ADDOPTS` unchanged when no invalid `--cache-dir` flag is present.
Design: Return immediately without modifying the environment when `PYTEST_ADDOPTS` does not contain `--cache-dir=`.
Tests:
- R001-T01: Verify unchanged addopts pass through untouched.

R005  Statement: Strip invalid `--cache-dir` from `PYTEST_ADDOPTS` and warn the operator.
Design: Remove `--cache-dir=...` tokens from `PYTEST_ADDOPTS`, normalize whitespace, unset when empty, and emit a stderr warning.
Tests:
- R005-T01: Verify invalid cache-dir flags are removed while other addopts remain.
