---
name: sqlcipher-migration
overview: Replace plaintext SQLite usage with SQLCipher across runtime, shell scripts, and tests while starting fresh encrypted databases (no legacy conversion). Keep CLI-based SQL flows by swapping sqlite3 invocations for sqlcipher wrappers and centralizing key handling.
todos:
  - id: deps-prereqs
    content: Add SQLCipher dependency, prerequisite install updates, and binary-integrity policy adjustments
    status: completed
  - id: key-plumbing
    content: Introduce SQLCipher key fields/exports in DB profile and script env plumbing
    status: completed
  - id: runtime-connect
    content: Switch runtime and tooling SQLite connect paths to SQLCipher with key-first PRAGMA flow
    status: completed
  - id: shell-lanes
    content: Replace sqlite3 shell invocations with SQLCipher wrappers in deploy/verify/test scripts
    status: completed
  - id: tests-docs
    content: Update shell/python tests and README for encrypted SQLite behavior
    status: completed
isProject: false
---

# SQLCipher Migration Plan

## Scope And Decisions
- Use SQLCipher for all SQLite-backed operations.
- Start with new encrypted databases only (no plaintext migration path).
- Keep shell-driven deploy/verify/test flows, but replace `sqlite3` calls with SQLCipher-aware wrappers.

## Implementation Steps
- Update dependency and prerequisite surfaces so SQLCipher is installable and expected:
  - [`/Users/phil/local/src/teller/requirements.in`](/Users/phil/local/src/teller/requirements.in)
  - [`/Users/phil/local/src/teller/requirements.txt`](/Users/phil/local/src/teller/requirements.txt)
  - [`/Users/phil/local/src/teller/01_install_prerequisites.sh`](/Users/phil/local/src/teller/01_install_prerequisites.sh)
  - [`/Users/phil/local/src/teller/config/security/binary-integrity-policy.json`](/Users/phil/local/src/teller/config/security/binary-integrity-policy.json)
- Add SQLCipher key plumbing in profile/config export so both Python and shell lanes can read one canonical key source:
  - [`/Users/phil/local/src/teller/src/teller/teller_db_profile.py`](/Users/phil/local/src/teller/src/teller/teller_db_profile.py)
  - [`/Users/phil/local/src/teller/src/scripts/db_profile_export.sh`](/Users/phil/local/src/teller/src/scripts/db_profile_export.sh)
  - [`/Users/phil/local/src/teller/config/db-profiles-EXAMPLE.json`](/Users/phil/local/src/teller/config/db-profiles-EXAMPLE.json)
- Convert runtime DB connection path to SQLCipher-capable connect flow:
  - [`/Users/phil/local/src/teller/src/teller/teller_db.py`](/Users/phil/local/src/teller/src/teller/teller_db.py)
  - [`/Users/phil/local/src/teller/tools/compare_postgres_sqlite.py`](/Users/phil/local/src/teller/tools/compare_postgres_sqlite.py)
  - Ensure connect sequence is key-first, then existing `PRAGMA foreign_keys = ON`, then `ATTACH DATABASE` behavior.
- Replace shell SQL execution calls and keep behavior parity:
  - [`/Users/phil/local/src/teller/06_deploy_database.sh`](/Users/phil/local/src/teller/06_deploy_database.sh)
  - [`/Users/phil/local/src/teller/tests/t05_deploy_database_verification_test.sh`](/Users/phil/local/src/teller/tests/t05_deploy_database_verification_test.sh)
  - [`/Users/phil/local/src/teller/src/scripts/run_unit_test_lanes.sh`](/Users/phil/local/src/teller/src/scripts/run_unit_test_lanes.sh)
  - Introduce a shared SQLCipher invocation helper (or consistent inline wrapper) so key injection is identical across scripts.
- Update tests and docs to lock in encrypted-db expectations:
  - Shell tests under [`/Users/phil/local/src/teller/tests/sh`](/Users/phil/local/src/teller/tests/sh)
  - Python tests: [`/Users/phil/local/src/teller/tests/py/test_teller_db.py`](/Users/phil/local/src/teller/tests/py/test_teller_db.py), [`/Users/phil/local/src/teller/tests/py/test_teller_db_profile.py`](/Users/phil/local/src/teller/tests/py/test_teller_db_profile.py), [`/Users/phil/local/src/teller/tests/py/test_compare_postgres_sqlite.py`](/Users/phil/local/src/teller/tests/py/test_compare_postgres_sqlite.py)
  - Operator docs: [`/Users/phil/local/src/teller/README.md`](/Users/phil/local/src/teller/README.md)

## Validation
- Run shell lanes covering prerequisites, deploy, SQL unit tests, backup/restore, and verification.
- Run Python unit tests focused on DB profile and engine connection behavior.
- Confirm failure mode is explicit when key is missing/incorrect.
- Confirm no logs expose SQLCipher key material.
