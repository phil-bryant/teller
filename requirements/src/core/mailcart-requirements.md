# Core Mailcart Client Requirements

## Scope

Applies to `src/core/include/tellercore/mailcart.hpp` and `src/core/src/mailcart.cpp`.

R001  Statement: Mailcart client helpers validate endpoint configuration and execute message retrieval/search requests through the shared HTTP abstraction.
Design: The mailcart interface and implementation validate HTTPS endpoints, construct HTTP clients, and issue API requests used by downstream classifier/runtime integrations.
Tests:
- R001-T01: Verify each mapped source file carries scoped `#R001:` tags and module symbols via `tests/sh/mailcart.bats`.

## Changelog

- 2026-06-14: Added module-level traceability requirements for tellercore first-party native enforcement.
