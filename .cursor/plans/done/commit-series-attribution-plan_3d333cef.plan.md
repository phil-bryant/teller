---
name: commit-series-attribution-plan
overview: "Create an ordered set of non-amended commits that groups the current working-tree changes by intent: supply-chain prep, DB shell/test stabilization, dependency freshness/reporting updates, and DAST/classification hardening."
todos:
  - id: group-files-by-commit
    content: Stage and verify files for commit 1 (supply-chain hardening cluster).
    status: completed
  - id: commit-db-stabilization
    content: Create commit 2 for DB script env isolation and compare-postgres-sqlite traceability updates.
    status: completed
  - id: commit-freshness-updates
    content: Create commit 3 for dependency freshness direct requirements and generated artifacts.
    status: completed
  - id: commit-dast-classifier
    content: Create commit 4 for DAST fixture/lane and classifier/UI stabilization changes.
    status: completed
  - id: commit-plan-artifacts
    content: Create commit 5 for .cursor plan artifacts and verify clean git status.
    status: completed
isProject: false
---

# Commit Series to Attribute Existing Changes

## Goal
Produce a clean, reviewable sequence of commits that attributes all current repo changes to their intended workstreams, while avoiding `--amend`.

## Commit order and scope

1. **Supply-chain integrity command hardening + test alignment**
   - Files:
     - [03_prepare_supply_chain_integrity.sh](03_prepare_supply_chain_integrity.sh)
     - [tests/sh/03_prepare_supply_chain_integrity.bats](tests/sh/03_prepare_supply_chain_integrity.bats)
     - [requirements/03_prepare_supply_chain_integrity-requirements.md](requirements/03_prepare_supply_chain_integrity-requirements.md)
     - [tests/sh/t01_run_av_test.bats](tests/sh/t01_run_av_test.bats)
   - Rationale: these changes all align the supply-chain prep flow around `pip-compile` availability behavior and associated requirement/test traceability updates.
   - Suggested message: `Harden supply-chain prep around pip-compile and align shell tests.`

2. **DB shell profile-leak guards + compare script traceability coverage**
   - Files:
     - [98_destroy_database.sh](98_destroy_database.sh)
     - [99_restore_database.sh](99_restore_database.sh)
     - [tools/compare_postgres_sqlite.py](tools/compare_postgres_sqlite.py)
     - [tests/py/test_compare_postgres_sqlite.py](tests/py/test_compare_postgres_sqlite.py)
     - [requirements/src/scripts/compare_postgres_sqlite-requirements.md](requirements/src/scripts/compare_postgres_sqlite-requirements.md)
   - Rationale: these changes are DB-oriented stabilization/traceability updates (profile export hygiene in DB scripts plus compare tool requirement/test linkage).
   - Suggested message: `Stabilize DB script environment loading and add postgres/sqlite compare traceability tests.`

3. **Dependency freshness direct-requirements gate update + lock/report refresh**
   - Files:
     - [src/scripts/check_dependency_freshness.py](src/scripts/check_dependency_freshness.py)
     - [tests/py/test_check_dependency_freshness.py](tests/py/test_check_dependency_freshness.py)
     - [requirements/src/scripts/check_dependency_freshness-requirements.md](requirements/src/scripts/check_dependency_freshness-requirements.md)
     - [requirements.txt](requirements.txt)
     - [artifacts/quality/reports/radon.txt](artifacts/quality/reports/radon.txt)
   - Rationale: the script now distinguishes direct requirements source behavior (defaulting to `.in`/override), and the associated requirement text/tests/artifacts reflect that updated behavior.
   - Suggested message: `Update dependency freshness direct-requirements gating and refresh generated reports.`

4. **DAST/matchy fixture seeding hardening + classifier token fallback + UI stability**
   - Files:
     - [src/scripts/security/run_dynamic_security_lane.sh](src/scripts/security/run_dynamic_security_lane.sh)
     - [tests/py/security/schemathesis_fixture_prep.py](tests/py/security/schemathesis_fixture_prep.py)
     - [src/teller/classification/auth.py](src/teller/classification/auth.py)
     - [src/teller/teller_classification_api.py](src/teller/teller_classification_api.py)
     - [src/teller/classification/constants.py](src/teller/classification/constants.py)
     - [src/macos-ui/UITests/TransactionClassifierUITests.swift](src/macos-ui/UITests/TransactionClassifierUITests.swift)
   - Rationale: these changes all support DAST/classifier reliability (better seeded candidate handling, safer schema constraints, env write-token support, SQL template robustness, and flaky UI delete stabilization).
   - Suggested message: `Harden DAST matchy seeding and stabilize classifier auth/UI test behavior.`

5. **Record planning artifacts from prior agent runs**
   - Files:
     - [.cursor/plans/stabilize-dast-shell-parse_2fc23a5a.plan.md](.cursor/plans/stabilize-dast-shell-parse_2fc23a5a.plan.md)
     - [.cursor/plans/stabilize-t07-db-shell-tests_ceaa072d.plan.md](.cursor/plans/stabilize-t07-db-shell-tests_ceaa072d.plan.md)
   - Rationale: these appear to be generated planning artifacts for the stabilization efforts and should be committed separately as metadata.
   - Suggested message: `Add completed stabilization plan artifacts for DAST and t07 follow-up.`

## Execution checklist (no amend)
- For each commit, stage only that commit’s file list.
- Run a quick scope check before committing:
  - `git diff --cached --name-only`
  - `git diff --cached`
- Commit with the suggested message style (or your preferred equivalent).
- Repeat until all five commits are created.
- Final verification:
  - `git status --short` returns clean working tree.
  - `git log --oneline -5` shows the intended ordered series.

## Notes on attribution choices
- `requirements.txt` and `artifacts/quality/reports/radon.txt` are treated as generated outputs tied to the dependency freshness change set, because that is where behavior/report shape changed.
- The `.cursor/plans/*` files are intentionally isolated so they do not obscure functional diffs in feature/fix commits.