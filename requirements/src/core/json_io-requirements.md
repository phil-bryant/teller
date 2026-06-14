# Core JSON IO Helpers Requirements

## Scope

Applies to `src/core/include/tellercore/json_io.hpp` and `src/core/src/json_io.cpp`.

R001  Statement: JSON IO helpers provide stable row/value serialization and UTC timestamp formatting for core adapters and FFI responses.
Design: The JSON IO interface and implementation convert database rows/values into JSON structures and normalize UTC timestamp rendering for cross-language API contracts.
Tests:
- R001-T01: Verify each mapped source file carries scoped `#R001:` tags and module symbols via `tests/sh/json_io.bats`.

## Changelog

- 2026-06-14: Added module-level traceability requirements for tellercore first-party native enforcement.
