# Core Oracle Comparators Requirements

## Scope

Applies to `src/core/oracle/compare_oracle.py` and `src/core/oracle/compare_statement_oracle.py`.

R001  Statement: Core oracle comparator scripts assert Python/C++ parity for persist and statement parsing scenarios.
Design: The oracle scripts execute Python and C++ runners on shared fixtures and fail on snapshot mismatches to protect cross-implementation parity.
Tests:
- R001-T01: Verify each mapped source file carries scoped `#R001:` tags and module symbols via `tests/sh/core_oracle.bats`.

## Changelog

- 2026-06-14: Added module-level traceability requirements for tellercore first-party native enforcement.
