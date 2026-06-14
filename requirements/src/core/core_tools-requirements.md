# Core Tooling CLIs Requirements

## Scope

Applies to `src/core/tools/oracle_runner.cpp`, `src/core/tools/teller_backfill.cpp`, and `src/core/tools/teller_fetch.cpp`.

R001  Statement: Core CLI tools orchestrate fetch/backfill/oracle workflows on top of tellercore APIs and profile-aware DB connections.
Design: The tool executables parse command-line inputs and execute ingest, reconciliation, and oracle replay flows through shared core services.
Tests:
- R001-T01: Verify each mapped source file carries scoped `#R001:` tags and module symbols via `tests/sh/core_tools.bats`.

## Changelog

- 2026-06-14: Added module-level traceability requirements for tellercore first-party native enforcement.
