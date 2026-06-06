---
name: stabilize failing test lanes
overview: Fix the three failing parallel lanes by hardening SQL secret fallback behavior, correcting DAST app-script resolution, and removing ShellCheck medium findings without lowering security gates.
todos:
  - id: sql-fallback-hardening
    content: Align runner secret fallback semantics with 1psa (including ITEM.password) and harden SQL lane credential resolution tests.
    status: completed
  - id: dast-path-and-preflight
    content: Fix stale DAST app script paths and add dynamic lane preflight validation + tests.
    status: completed
  - id: pointer-shellcheck-cleanup
    content: Modernize teller pointer scripts to use select_runbook_profile and remove SC2034 warnings.
    status: completed
  - id: verify-lanes
    content: Run targeted failing lanes and full parallel suite to confirm all three failures are resolved.
    status: completed
isProject: false
---

# Stabilize Teller Parallel Test Failures

## Scope
Address the 3 failing lanes from `./06_run_all_tests_parallel.sh` while keeping current security policy intact:
- SQL lane (`t06_run_sql_unit_tests.sh`)
- Dynamic security lane (`t11_run_dynamic_security_tests.sh`)
- Static security lane (`t03_run_static_security_tests.sh`)

## 1) Fix SQL lane secret-resolution robustness (1Password rate-limit safe)
- Update fallback helpers in [`../runner/src/scripts/runbook_common.sh`](../runner/src/scripts/runbook_common.sh) and mirrored helper logic in [`../runner/src/scripts/security/common.sh`](../runner/src/scripts/security/common.sh):
  - Make `rb_read_1psa_item` / env fallback semantics consistent with current `1psa` + profile behavior.
  - Ensure lookup order supports `"<ITEM>.password"` then `"<ITEM>"` from env/`.env`, not only the bare item key.
  - Keep bounded timeout behavior and improve diagnostics listing attempted fallback keys/sources.
- Update SQL lane password resolution in [`../runner/src/scripts/run_unit_test_lanes.sh`](../runner/src/scripts/run_unit_test_lanes.sh):
  - Use fallback order: explicit `TELLER_DB_PASSWORD` -> `rb_read_1psa_item` -> compatible env/`.env` fallback.
  - Apply parity logic to both primary (`PG_ONEPSA_ITEM`) and admin (`POSTGRES_PSA_ITEM`) password paths.
- Align teller DB verification flow in [`tests/t05_deploy_database_verification_test.sh`](tests/t05_deploy_database_verification_test.sh) to the same shared helper path (remove direct raw `1psa -p` drift).
- Add regression coverage:
  - [`../runner/tests/sh/runbook_common.bats`](../runner/tests/sh/runbook_common.bats): `ITEM.password` fallback and rate-limit/error fallback behavior.
  - [`../runner/tests/sh/run_unit_test_lanes.bats`](../runner/tests/sh/run_unit_test_lanes.bats): SQL lane succeeds with dotenv field fallback for both primary/admin password cases.

## 2) Fix DAST API startup path and make failures explicit
- Correct stale runbook path in [`../runner/config/runbook/teller.env`](../runner/config/runbook/teller.env):
  - `DAST_APP_SCRIPT` should point to the current classy API entrypoint (`../classy/06_run_classification_api.py`).
- Also align [`../runner/config/runbook/classy.env`](../runner/config/runbook/classy.env) to the same current entrypoint to prevent the same break in classy runs.
- Harden [`../runner/src/scripts/security/run_dynamic_security_lane.sh`](../runner/src/scripts/security/run_dynamic_security_lane.sh):
  - Add preflight validation that `DAST_APP_SCRIPT` exists before launch.
  - Emit a direct error (missing script path) instead of only surfacing as a later health-check timeout.
- Extend static-inspection coverage in [`../runner/tests/sh/run_dynamic_security_lane.bats`](../runner/tests/sh/run_dynamic_security_lane.bats) for the new preflight guard.

## 3) Clear SAST gate blockers without weakening policy
- Keep medium-or-higher gate behavior unchanged in SAST.
- Eliminate current ShellCheck findings (SC2034 on `RUNBOOK_PROFILE`) by modernizing top-level teller pointers to the shim contract:
  - Update root pointer scripts in [`01_install_prerequisites.sh`](01_install_prerequisites.sh), [`02_create_venv.sh`](02_create_venv.sh), [`03_prepare_supply_chain_integrity.sh`](03_prepare_supply_chain_integrity.sh), [`04_load_requirements.sh`](04_load_requirements.sh), [`05_deploy_database.sh`](05_deploy_database.sh), [`06_run_all_tests_parallel.sh`](06_run_all_tests_parallel.sh), [`07_report_quality_trends.sh`](07_report_quality_trends.sh), [`08_validate_quality_target.sh`](08_validate_quality_target.sh), [`09_prune_quality_telemetry.sh`](09_prune_quality_telemetry.sh), [`97_backup_database.sh`](97_backup_database.sh), [`98_destroy_database.sh`](98_destroy_database.sh), and [`99_restore_database.sh`](99_restore_database.sh).
  - Replace legacy `RUNBOOK_PROFILE=...` usage with explicit `select_runbook_profile "teller"` after sourcing `pointer_shim.sh`.
  - This removes unused-variable warnings and aligns with the current runner shim contract.

## 4) Verification pass (targeted then full)
- Re-run targeted failing lanes first:
  - `tests/t06_run_sql_unit_tests.sh`
  - `tests/t11_run_dynamic_security_tests.sh`
  - `tests/t03_run_static_security_tests.sh`
- Re-run `./06_run_all_tests_parallel.sh` end-to-end.
- Confirm artifacts show:
  - SQL lane no longer fails due to 1Password rate-limit when `.env` fallback is available.
  - DAST lane launches API successfully (or fails early with explicit missing-script diagnostic).
  - SAST `shellcheck_medium_or_higher` no longer blocked by pointer-script SC2034 warnings.