# Core 1psa Integration Requirements

## Scope

Applies to `src/core/include/tellercore/onepsa.hpp` and `src/core/src/onepsa.cpp`.

R001  Statement: 1psa integration helpers load secret fields/passwords with deterministic fallback behavior for profile resolution paths.
Design: The 1psa interface and implementation load linked secret-store symbols, read requested fields, and surface strict password-resolution errors for callers.
Tests:
- R001-T01: Verify each mapped source file carries scoped `#R001:` tags and module symbols via `tests/sh/onepsa.bats`.

## Changelog

- 2026-06-14: Added module-level traceability requirements for tellercore first-party native enforcement.
