# Core Profile Resolution Requirements

## Scope

Applies to `src/core/include/tellercore/profile.hpp` and `src/core/src/profile.cpp`.

R001  Statement: Profile resolution helpers load runtime configuration and credentials into validated DB profile objects.
Design: The profile interface and implementation resolve profile documents, environment/1psa overrides, and target-specific defaults for PostgreSQL and SQLite execution contexts.
Tests:
- R001-T01: Verify each mapped source file carries scoped `#R001:` tags and module symbols via `tests/sh/profile.bats`.

## Changelog

- 2026-06-14: Added module-level traceability requirements for tellercore first-party native enforcement.
