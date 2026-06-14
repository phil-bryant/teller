# Core OCR Backends Requirements

## Scope

Applies to `src/core/include/tellercore/ocr.hpp`, `src/core/src/ocr_backend_apple.mm`, and `src/core/src/ocr_backend_win.cpp`.

R001  Statement: OCR backend implementations normalize platform OCR observations into the shared tellercore OCR model.
Design: The OCR interface and platform implementations convert PDF/image OCR outputs into normalized observation/page structures consumed by statement parsing.
Tests:
- R001-T01: Verify each mapped source file carries scoped `#R001:` tags and module symbols via `tests/sh/ocr_backend.bats`.

## Changelog

- 2026-06-14: Added module-level traceability requirements for tellercore first-party native enforcement.
