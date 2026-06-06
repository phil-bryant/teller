# Teller Object Requirements

## Scope

Applies to `src/teller/teller_object.py`.

R001  Statement: Provide a shared Teller ORM base with timestamp columns in the `teller` schema.
Design: Define `TimestampMixin` with timezone-aware `created_at` and `updated_at`, and define `TellerObject` as an abstract model with `__table_args__ = {"schema": "teller"}`.
Tests:
- R001-T01: Instantiate a concrete subclass and verify `created_at`/`updated_at` default values are assigned.
- R001-T02: Verify generated tables for subclasses target the `teller` schema.

R005  Statement: Derive default SQLAlchemy table names from Teller model class names.
Design: Build `__tablename__` by removing `Teller` prefix and converting CamelCase segments to snake_case.
Tests:
- R005-T01: Define a concrete class such as `TellerTransactionDetails` and verify table name resolves to `transaction_details`.

R010  Statement: Support shared API client injection at class level.
Design: Implement `set_api_client(cls, client)` to assign `_api_client` for subclasses.
Tests:
- R010-T01: Call `set_api_client` on a subclass and verify subsequent instances can access the shared client reference.

R015  Statement: Initialize objects from optional API payload data.
Design: During `__init__`, store non-empty `api_data` on `_api_data` and trigger `__post_init__` hydration.
Tests:
- R015-T01: Instantiate with API payload and verify mapped fields are populated.
- R015-T02: Instantiate without API payload and verify no hydration pass runs.

R020  Statement: Map API payload keys to dataclass field names with optional column aliases.
Design: `_mapped_api_data()` inspects SQLAlchemy column `info["api_name"]` metadata when present and falls back to same-name mapping.
Tests:
- R020-T01: Add a field with `api_name` metadata and verify hydration reads the aliased payload key.
- R020-T02: Verify unmapped payload keys are ignored.

R025  Statement: Coerce mapped payload values to annotated target types when possible.
Design: `__post_init__` resolves type hints, unwraps list element types, and casts scalars/lists; on `TypeError`, `ValueError`, or `KeyError`, it preserves the original value.
Tests:
- R025-T01: Hydrate list-typed and scalar-typed fields and verify converted Python types.
- R025-T02: Provide non-castable input and verify raw value fallback is retained.
- R025-T03: Call annotation-unpack helper with list annotation and verify inner type extraction.

R030  Statement: Provide a concise debug string with selected field values.
Design: `__str__` includes values for dataclass fields marked with metadata `{"__str__": True}` and appends `_api_data`.
Tests:
- R030-T01: Mark fields with `__str__` metadata and verify string output includes only marked fields plus `_api_data`.

## Changelog

- 2026-04-22: Initial reverse-engineered requirements for `src/teller/teller_object.py`.
