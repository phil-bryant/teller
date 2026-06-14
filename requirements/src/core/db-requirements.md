# Core Database Layer Requirements

## Scope

Applies to `src/core/include/tellercore/db.hpp`, `src/core/include/tellercore/db_postgres.hpp`, `src/core/include/tellercore/dialect.hpp`, `src/core/src/db.cpp`, `src/core/src/db_postgres.cpp`, and `src/core/src/db_sqlite.cpp`.

R001  Statement: Core database adapters expose shared dialect-aware query and transaction primitives for SQLite and PostgreSQL flows.
Design: Implemented by the generic DB abstraction and backend-specific adapters in the listed headers/sources, which together provide dialect selection, statement execution, and transaction helpers used by persistence and tools.
Tests:
- R001-T01: Verify each mapped source file carries scoped `#R001:` tags and module symbols via `tests/sh/db.bats`.

## Changelog

- 2026-06-14: Added module-level traceability requirements for tellercore first-party native enforcement.
