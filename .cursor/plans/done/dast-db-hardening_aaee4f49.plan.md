---
name: dast-db-hardening
overview: Harden the classification system so fuzzed/authenticated DAST traffic cannot corrupt category taxonomy data, by enforcing invariants in both the database and API layer while preserving UI category management.
todos:
  - id: db-guardrails
    content: Design and add nys_snw_category seed-protection and row-validity constraints/triggers in SQL schema.
    status: completed
  - id: api-hardening
    content: Tighten category mutation request models/normalization and explicit error mapping in teller_classification_api.py.
    status: completed
  - id: dast-integrity-gate
    content: Rework post-DAST integrity invariants in 15_run_dast.sh to enforce prevention-focused checks.
    status: completed
  - id: tests-api-and-dast
    content: Expand API and DAST test suites to cover seed immutability, invalid payload rejection, and valid non-seed CRUD.
    status: completed
  - id: privilege-scope
    content: Adjust DB role/privilege setup toward least privilege for runtime app access without adding heavy infrastructure.
    status: completed
isProject: false
---

# DAST-Proof Category Integrity Plan

## Outcome
Prevent malformed or destructive category writes at the source (DB + API), while keeping runtime category management available in the UI and avoiding "scan tweaks" or post-attack cleanup as the primary defense.

## 1) Database Integrity As Source Of Truth
- Update [`/Users/phil/local/src/teller/sql/postgres/teller_nys_snw_category.sql`](/Users/phil/local/src/teller/sql/postgres/teller_nys_snw_category.sql) to introduce explicit taxonomy provenance and immutability controls for seed rows:
  - Add a provenance flag (e.g. `is_seed`) and seed canonical rows with it.
  - Add a guard trigger/function to reject `UPDATE`/`DELETE` on seed categories.
  - Keep runtime CRUD for non-seed rows, but enforce stricter CHECK invariants for all rows (non-empty meaningful hierarchy + printable/non-control text).
- Keep referential safety in [`/Users/phil/local/src/teller/sql/postgres/teller_transaction_nys_snw_category.sql`](/Users/phil/local/src/teller/sql/postgres/teller_transaction_nys_snw_category.sql), and verify behavior when deleting non-seed categories referenced by transactions (must continue to fail cleanly).
- Add least-privilege follow-up in [`/Users/phil/local/src/teller/sql/postgres/configure_database.sql`](/Users/phil/local/src/teller/sql/postgres/configure_database.sql) so runtime app credentials are not broad admin by default (leaner blast radius).

## 2) API Input Hardening (No Trust In Client)
- Refactor mutation models in [`/Users/phil/local/src/teller/teller/teller_classification_api.py`](/Users/phil/local/src/teller/teller/teller_classification_api.py):
  - Separate create vs update payload contracts (create requires meaningful category content; update can be partial but cannot null-out into invalid state).
  - Normalize and validate Unicode safely (reject control/format/non-printable payloads before SQL).
  - Tighten field-level constraints (length, allowed character class, non-empty semantics), and surface deterministic 4xx errors.
- Ensure delete/update routes explicitly reject seed-protected categories with stable conflict responses.
- Map DB constraint violations to clear API errors (`409`/`422`) rather than generic `400` to improve contract reliability under fuzzing.

## 3) DAST Gate Rework To Validate Prevention (Not Cleanup)
- Update [`/Users/phil/local/src/teller/15_run_dast.sh`](/Users/phil/local/src/teller/15_run_dast.sh) integrity checks so they validate durable invariants:
  - Seed taxonomy rows remain unchanged (no missing/altered/deleted seed rows).
  - No invalid text/control-char rows can be persisted.
  - No empty hierarchy rows.
  - No orphaned transaction-category links.
- Remove the current assumption that all IDs must stay within seed range (since UI-managed non-seed categories are valid), and instead assert seed protection + row validity.
- Keep full-strength Schemathesis/ZAP behavior; do not weaken attack corpus or move target scope.

## 4) Verification Coverage
- Extend Python API tests in [`/Users/phil/local/src/teller/tests/py/test_teller_classification_api.py`](/Users/phil/local/src/teller/tests/py/test_teller_classification_api.py):
  - Fuzz-like invalid payload rejection (control chars, empty-but-present objects, invalid Unicode forms).
  - Seed row update/delete rejection.
  - Non-seed CRUD still works for valid data.
- Extend shell/DAST tests in [`/Users/phil/local/src/teller/tests/sh/15_run_dast.bats`](/Users/phil/local/src/teller/tests/sh/15_run_dast.bats) to assert hardened integrity gate semantics.
- Add SQL-level invariants test coverage (pgTAP-style) so DB constraints are independently enforced even if API validation regresses.

## 5) Rollout Strategy (Lean)
- Apply schema hardening first, then API changes, then DAST/test updates.
- Include one compatibility pass for existing rows so deployment fails fast with actionable violations if preexisting bad data exists, but keep prevention mechanisms as the core fix.
- Preserve current UI category-management flow end-to-end with no extra external service dependencies.