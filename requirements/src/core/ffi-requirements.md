# Core FFI Envelope Requirements

## Scope

Applies to `src/core/include/tellercore/error.hpp`, `src/core/include/tellercore/ffi.h`, and `src/core/src/ffi.cpp`.

R001  Statement: The tellercore FFI boundary validates inputs, dispatches operations, and returns JSON envelopes with consistent error semantics.
Design: The FFI headers and implementation expose the C ABI entrypoints and error envelope contract used by external runtimes embedding tellercore.
Tests:
- R001-T01: Verify each mapped source file carries scoped `#R001:` tags and module symbols via `tests/sh/ffi.bats`.

## Changelog

- 2026-06-14: Added module-level traceability requirements for tellercore first-party native enforcement.
