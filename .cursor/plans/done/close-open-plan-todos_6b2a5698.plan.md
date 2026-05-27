---
name: close-open-plan-todos
overview: Validate and close the two still-relevant verification todos, and formally retire the superseded parallel-regression todo so the remaining committed plans accurately reflect reality.
todos:
  - id: verify-ui-regression-closure
    content: Run current UI-regression verification commands and close or split `verify-suite` based on results.
    status: completed
  - id: verify-clutter-migration-closure
    content: Run migration-focused lane matrix and close or split `verify-and-cleanup` based on evidence.
    status: completed
  - id: retire-stale-parallel-todo
    content: Mark `full-regression` as superseded by completed follow-up plan and renumbered scripts.
    status: completed
isProject: false
---

# Close Remaining Committed Plan Todos

## Assessment
- **`verify-suite` in [`/Users/phil/local/src/teller/.cursor/plans/redo_ui_regression_10_0c01ef49.plan.md`](/Users/phil/local/src/teller/.cursor/plans/redo_ui_regression_10_0c01ef49.plan.md)**
  - **Still relevant:** Yes.
  - **Evidence of implementation:** Strong (single-session smoke suite and selector plumbing are present in [`/Users/phil/local/src/teller/src/macos-ui/UITests/TransactionClassifierUITests.swift`](/Users/phil/local/src/teller/src/macos-ui/UITests/TransactionClassifierUITests.swift), [`/Users/phil/local/src/teller/tests/t14_run_macos_ui_regression_tests.sh`](/Users/phil/local/src/teller/tests/t14_run_macos_ui_regression_tests.sh), [`/Users/phil/local/src/teller/tests/sh/t14_run_macos_ui_regression_tests.bats`](/Users/phil/local/src/teller/tests/sh/t14_run_macos_ui_regression_tests.bats), and [`/Users/phil/local/src/teller/requirements/t14_run_macos_ui_regression_tests-requirements.md`](/Users/phil/local/src/teller/requirements/t14_run_macos_ui_regression_tests-requirements.md)).
  - **Why still open:** No recorded proof run tied to the todo; plan still references pre-renumber script names.
  - **Decision:** Execute verification commands with current paths and then close.

- **`verify-and-cleanup` in [`/Users/phil/local/src/teller/.cursor/plans/clutter-13-migration_31111c52.plan.md`](/Users/phil/local/src/teller/.cursor/plans/clutter-13-migration_31111c52.plan.md)**
  - **Still relevant:** Yes.
  - **Evidence of implementation:** Strong path migration adoption exists (for example in [`/Users/phil/local/src/teller/pyproject.toml`](/Users/phil/local/src/teller/pyproject.toml), [`/Users/phil/local/src/teller/src/scripts/security/run_static_security_lane.sh`](/Users/phil/local/src/teller/src/scripts/security/run_static_security_lane.sh), [`/Users/phil/local/src/teller/src/teller/teller_db_profile.py`](/Users/phil/local/src/teller/src/teller/teller_db_profile.py), and [`/Users/phil/local/src/teller/README.md`](/Users/phil/local/src/teller/README.md)).
  - **Why still open:** Final migration verification/legacy cleanup policy was not explicitly closed in the plan artifact.
  - **Decision:** Run migration-focused verification matrix and either complete todo or split true leftovers into a new narrow follow-up.

- **`full-regression` in [`/Users/phil/local/src/teller/.cursor/plans/parallel-failures-remediation_d9847d19.plan.md`](/Users/phil/local/src/teller/.cursor/plans/parallel-failures-remediation_d9847d19.plan.md)**
  - **Still relevant:** Mostly **superseded**.
  - **Evidence of supersession:** A later completed plan already records full revalidation (`revalidate-all`) in [`/Users/phil/local/src/teller/.cursor/plans/done/fix-parallel-failures_1030ed6d.plan.md`](/Users/phil/local/src/teller/.cursor/plans/done/fix-parallel-failures_1030ed6d.plan.md).
  - **Why still open:** Stale artifact (also references old `24_run_all_tests_parallel.sh` naming).
  - **Decision:** Do not re-open this old remediation line item; mark as superseded/closed with a cross-reference.

## Execution Plan
1. **Run UI-regression closure verification**
   - Execute current equivalent checks:
     - `xcodebuild ... -only-testing:TransactionClassifierUITests/TransactionClassifierUITests/testMacOSUISmokeSuite`
     - `./tests/t14_run_macos_ui_regression_tests.sh`
     - `./tests/t14_run_macos_ui_regression_tests.sh 3,6`
     - `bats tests/sh/t14_run_macos_ui_regression_tests.bats`
   - Capture pass/fail evidence in commit message notes or plan changelog text.

2. **Run clutter-migration closure verification**
   - Execute the impacted-lane set (current numbering):
     - `./tests/t02_run_dependency_freshness_tests.sh`
     - `./tests/t03_run_static_security_tests.sh`
     - `./tests/t09_run_mutation_tests.sh`
     - `./tests/t12_run_dynamic_security_tests.sh`
     - `./tests/t10_run_all_tests_parallel.sh`
   - Confirm outputs land in canonical destinations under `artifacts/*`, `config/*`, and `requirements/security/*`.
   - Verify legacy-root items from the original 13-item list are absent or intentionally fallback-only.

3. **Close or split based on evidence**
   - If checks pass: mark `verify-suite` and `verify-and-cleanup` as completed and move/close plan artifacts per repository convention.
   - If checks fail: create one new focused plan per actual failing area (UI lane vs clutter-path regression), not a broad umbrella redo.

4. **Retire stale parallel-remediation todo**
   - Update [`/Users/phil/local/src/teller/.cursor/plans/parallel-failures-remediation_d9847d19.plan.md`](/Users/phil/local/src/teller/.cursor/plans/parallel-failures-remediation_d9847d19.plan.md) to mark `full-regression` as superseded by the completed plan and by current `10_*` numbering.
   - Keep historical context; avoid re-running obsolete command references solely to satisfy stale text.

## Done Criteria
- Two relevant open todos (`verify-suite`, `verify-and-cleanup`) are either completed with fresh evidence or split into precise follow-up plans.
- One stale todo (`full-regression`) is explicitly retired as superseded.
- No committed plan in `.cursor/plans/` remains open due only to outdated naming/history drift.