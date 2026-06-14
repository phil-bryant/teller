# Core Statement Parsing Requirements

## Scope

Applies to `src/core/include/tellercore/statement.hpp` and `src/core/src/statement.cpp`.

R001  Statement: Statement parsing helpers reconstruct OCR text into deterministic transaction records and identifiers.
Design: The statement parser interface and implementation provide OCR line reconstruction, transaction extraction, summary parsing, and deterministic txn-id generation used by backfill/oracle lanes.
Tests:
- R001-T01: Verify each mapped source file carries scoped `#R001:` tags and module symbols via `tests/sh/statement.bats`.

## Changelog

- 2026-06-14: Added module-level traceability requirements for tellercore first-party native enforcement.
