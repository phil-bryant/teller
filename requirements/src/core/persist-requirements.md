# Core Persist Layer Requirements

## Scope

Applies to `src/core/include/tellercore/persist.hpp` and `src/core/src/persist.cpp`.

R001  Statement: Persist helpers normalize API payloads into stable upsert/reconciliation workflows across supported database targets.
Design: The persist interface and implementation coordinate transaction normalization, idempotent upserts, relation reconciliation, and statement ingest planning used by fetch/backfill paths.
Tests:
- R001-T01: Verify each mapped source file carries scoped `#R001:` tags and module symbols via `tests/sh/persist.bats`.

## Changelog

- 2026-06-14: Added module-level traceability requirements for tellercore first-party native enforcement.
