---
name: shell-unit-test-strategy
overview: "Design a hybrid test strategy: add shell unit tests where deterministic behavior can be isolated, keep integration-only scripts out of unit scope, and define a unified runner flow for shell + Python tests."
todos:
  - id: catalog-shell-targets
    content: Map Tier 1/Tier 2 shell scripts to concrete bats test files and requirement IDs.
    status: completed
  - id: design-shell-fixtures
    content: Define reusable test harness helpers for sandboxed HOME, PATH command stubs, and output assertions.
    status: completed
  - id: plan-runner-update
    content: Specify hybrid runner flow and flags in 04_run_unit_tests.sh without breaking existing unittest behavior.
    status: completed
  - id: sequence-rollout
    content: Stage implementation in Tier 1 first, then Tier 2, with traceability verification checkpoints.
    status: completed
isProject: false
---

# Shell Script Unit Test + Runner Plan

## Assumption
Using the hybrid approach (your `c` response): `bats-core` for shell unit tests plus existing Python `unittest`.

## Constraints From Current Project Rules/Docs
- Source of truth for behavior is per-script requirements docs in [`requirements/`](requirements/) and workflow guidance in [`README.md`](README.md).
- Traceability gate in [`00_verify_requirements_traceability.sh`](00_verify_requirements_traceability.sh) must remain green when test-relevant requirements are updated.
- [`03_load_requirements.sh`](03_load_requirements.sh) is locked for edits, so tests must treat it as black-box behavior.
- No existing CI workflows; runner design should support local-first execution now and CI adoption later.

## Script Testability Tiers (What Should Have Unit Tests)

### Tier 1: High-value shell unit tests (add now)
- [`00_verify_requirements_traceability.sh`](00_verify_requirements_traceability.sh)
  - Why: Pure parsing/diff logic; deterministic and safety-critical.
  - Unit tests:
    - discovers requirement IDs and source `#R` tags correctly
    - passes when sets match, fails on missing/extra IDs
    - `--help`, zero-arg batch mode, two-arg pair mode, invalid arg count
    - locked-file exception policy handling
- [`01_install_prerequisites.sh`](01_install_prerequisites.sh)
  - Why: Orchestration-heavy but mockable; frequent contributor touchpoint.
  - Unit tests:
    - exits with clear error when `brew` missing
    - skips installs when `go/git/1psa` already on PATH
    - clone/install path decisions (`pg_install` exists as git dir vs conflicting non-git path)
    - `PSA_INSTALL_SUDO_ITEM` override wiring
- [`02_create_venv.sh`](02_create_venv.sh)
  - Why: Deterministic environment checks and venv naming logic.
  - Unit tests:
    - fails when prereq script path missing
    - interpreter selection preference (`python3.12` then `python3`)
    - refuses when `VIRTUAL_ENV` set
    - idempotent exit when venv exists
- [`07_configure_teller_io.sh`](07_configure_teller_io.sh)
  - Why: Rich branch logic around file provisioning; can be tested with command stubs.
  - Unit tests:
    - creates `~/.teller` with expected permissions
    - source precedence (existing file > env > 1psa)
    - examples repo behavior for skip/clone/conflict path
    - smoke-test skip/fail branches with stubbed `curl/jq`
- [`08_capture_teller_token.sh`](08_capture_teller_token.sh)
  - Why: Most complex shell logic; high regression risk.
  - Unit tests:
    - mode routing (`--list`, `--delete`, `--reconnect`, `--add`, `--manual`, `--clipboard`)
    - context selection ambiguity/missing selectors
    - suffix sanitization + uniqueness behavior
    - token file atomic write/permissions
    - verification skip paths when deps/files missing
- [`99_restore_database.sh`](99_restore_database.sh)
  - Why: Critical safety checks and argument parsing.
  - Unit tests:
    - `--from`/`--table` parsing and defaults to latest backup
    - dependency checks (`1psa`, `pg_restore`, `psql`)
    - refuses full restore when schema exists
    - table-scoped mode argument derivation

### Tier 2: Medium-value unit tests (add after Tier 1)
- [`97_backup_database.sh`](97_backup_database.sh)
  - command availability checks, password-empty guard, output path naming and permission steps.
- [`98_destroy_database.sh`](98_destroy_database.sh)
  - confirmation gate behavior and idempotent drop command sequence.
- [`04_run_unit_tests.sh`](04_run_unit_tests.sh)
  - root-dir normalization and venv auto-activation branch behavior.
- [`14_run_transaction_classifier.sh`](14_run_transaction_classifier.sh)
  - wrapper contract: forwards args and package path to `swift run`.

### Tier 3: Keep as integration/E2E verifiers (no unit-test investment now)
- [`05_deploy_database.sh`](05_deploy_database.sh)
- [`06_verify_deploy_database.sh`](06_verify_deploy_database.sh)
- [`12_verify_reclassification_persistence.sh`](12_verify_reclassification_persistence.sh)
- [`13_verify_updated_at_trigger_coverage.sh`](13_verify_updated_at_trigger_coverage.sh)

Rationale: these primarily validate real Postgres/API state; best tested with integration environments rather than heavy command-mocking that duplicates SQL semantics.

### Out of scope for unit tests
- [`archive/legacy/rename_files.sh`](archive/legacy/rename_files.sh) (legacy one-off utility).
- `teller-connect-ui` shell scripts (upstream example clone behavior, not first-party contract).

## Unit Test Design Best Practices (Shell)
- Use `bats-core` with helper libs (`bats-support`, `bats-assert`) for readable assertions.
- Use per-test temporary sandboxes (`TMPDIR`, fake `HOME`, isolated repo fixture dirs).
- Mock external commands by prepending a `test-bin` directory to `PATH` (stubs for `brew`, `git`, `1psa`, `psql`, `curl`, `jq`, `pg_dump`, `pg_restore`, etc.).
- Assert behavior contract, not implementation details: exit codes, key output lines, file artifacts/permissions, and called-command traces.
- Keep network/DB out of unit tests; reserve those for integration scripts.
- Add negative-path tests for each required failure condition documented in `requirements/*.md`.

## Test Runner Plan
- Add shell test suite under [`tests/sh/`](tests/sh/) with one file per target script (e.g., `00_verify_requirements_traceability.bats`, `08_capture_teller_token.bats`).
- Add shared helpers under [`tests/sh/helpers/`](tests/sh/helpers/) for sandbox setup, PATH stubs, and assertion utilities.
- Keep existing Python tests under [`tests/`](tests/) unchanged.
- Update [`04_run_unit_tests.sh`](04_run_unit_tests.sh) to orchestrate both suites in order:
  1) run shell unit tests (`bats tests/sh`)
  2) run Python unit tests (`python3 -m unittest discover tests`)
- Add optional flags/environment for local ergonomics:
  - `RUN_SHELL_TESTS=true|false`
  - `RUN_PYTHON_TESTS=true|false`
  - `BATS_FILTER=<pattern>` for focused shell runs
- Introduce a lightweight dependency check in runner with actionable install message if `bats` is missing.
- Ensure runner exits non-zero on first failing suite and prints concise suite summary.

## Rollout Sequence
1. Add shell test harness scaffolding (`tests/sh`, helpers, command stubs).
2. Implement Tier 1 tests in priority order: `00` -> `08` -> `07` -> `99` -> `02` -> `01`.
3. Integrate runner updates in [`04_run_unit_tests.sh`](04_run_unit_tests.sh).
4. Add Tier 2 tests as follow-up once Tier 1 is stable.
5. Run full local verification path: traceability script + hybrid unit runner.

## Success Criteria
- High-risk shell logic has deterministic, isolated unit coverage.
- Integration verifiers remain integration-focused (not over-mocked).
- Single command runner executes shell + Python unit suites and fails fast on regressions.
- Added tests map cleanly to requirement statements in [`requirements/`](requirements/) for maintainability.