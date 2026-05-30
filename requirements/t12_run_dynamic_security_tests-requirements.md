# Run DAST Requirements

## Scope

Applies to:
- `tests/t12_run_dynamic_security_tests.sh`
- `src/scripts/security/run_dynamic_security_lane.sh`

## Ownership Boundaries

This document owns DAST lane orchestration and hygiene policy.
Helper implementation details are owned by:
- `requirements/src/scripts/dast_baseline-requirements.md`
- `requirements/src/scripts/dast_cleanup-requirements.md`
- `requirements/src/scripts/cleanup_legacy_dast_artifacts-requirements.md`

R001  Statement: Print an explicit DAST startup banner.
Design: Emit `running DAST (Dynamic Application Security Testing)` at script startup before scanner orchestration begins.
Tests:
- R001-T01: Run script with `RUN_DAST=false` and verify startup output includes the exact banner string.

R005  Statement: Execute from repository root in strict shell mode.
Design: Use `set -euo pipefail`, resolve script directory from `${BASH_SOURCE[0]}`, and `cd` into that directory.
Tests:
- R005-T01: Run from a non-root working directory and verify relative paths still resolve.

R010  Statement: Bootstrap isolated security toolchain environment before running DAST dependencies.
Design: Create `SECURITY_VENV_DIR` when missing, install `requirements/security/requirements-security.txt` when `semgrep` is absent in that venv, and prepend `${SECURITY_VENV_DIR}/bin` to `PATH`.
Tests:
- R010-T01: Remove `artifacts/venv/security`, run script, and verify venv creation plus tool installation path executes.

R015  Statement: Run the dynamic security lane by default.
Design: Set `RUN_DAST=true` default and `RUN_SAST=false` default; run DAST scanners and DAST gate checks when enabled.
Tests:
- R015-T01: Run with defaults and verify DAST output includes lane completion markers.

R020  Statement: Emit explicit completion status and artifact location.
Design: Print DAST progress markers and final success output including resolved report directory path.
Tests:
- R020-T01: Run a passing DAST lane and verify completion output includes report directory.

R030  Statement: Emit machine-readable ZAP severity summary and enforce configurable threshold gates.
Design: Parse ZAP HTML quick-scan summary into JSON severity counts (`high`, `medium`, `low`, `informational`) and fail the DAST gate when findings meet/exceed `SECURITY_ZAP_FAIL_THRESHOLD` (default `high`) unless threshold is `none`.
Tests:
- R030-T01: Run with `RUN_ZAP=true` and verify `zap-classification-summary.json` is generated with severity counts.
- R030-T02: Set `SECURITY_ZAP_FAIL_THRESHOLD=medium` and verify medium-or-higher findings fail the lane.

R035  Statement: Treat Schemathesis contract findings as blocking by default.
Design: If Schemathesis exits with findings status (`exit 1`), fail the DAST lane unless `SCHEMATHESIS_FAIL_ON_FINDINGS=false` is explicitly set for diagnostic/non-blocking runs.
Tests:
- R035-T01: Verify default behavior exits non-zero when Schemathesis returns findings.
- R035-T02: Verify `SCHEMATHESIS_FAIL_ON_FINDINGS=false` preserves optional non-blocking execution.

R040  Statement: DAST local service ports must not collide.
Design: When local Schemathesis support starts both the classifier API and Mailcart HTTPS stub, the script must auto-resolve port collisions so the Mailcart stub never binds to the same host:port as the classifier API.
Tests:
- R040-T01: Verify lane logic contains explicit host+port collision handling and emits a collision auto-selection message.

R045  Statement: Schemathesis runtime state must stay in DAST artifacts, not repo root.
Design: Execute `schemathesis run` from the resolved DAST report directory so `.schemathesis/` is created beneath `artifacts/security-dast` (or custom report dir) instead of repository root.
Tests:
- R045-T01: Run DAST with Schemathesis enabled and verify `.schemathesis/` appears under the report directory.
- R045-T02: Verify DAST run does not create `${repo_root}/.schemathesis/`.

R025  Statement: DAST run must not leak state to the target database.
Design: Generate a per-run `DAST_RUN_ID` tag, capture a pre-run baseline via `src/scripts/dast_baseline.py` (max IDs plus full mutable-field snapshots of `nys_snw_category`, `transaction_email_match`, `transaction_email_match_audit`, and `transaction_nys_snw_category`), embed `DAST_RUN_ID` in seeded `categorization` and `email_message_id` payloads, and install an `EXIT` trap that invokes `src/scripts/dast_cleanup.py` to restore mutated rows and delete rows inserted past the baseline (FK-safe order: match restore -> audit delete -> match delete -> classification reconcile -> category delete -> category restore). The cleanup runs both on the success path (before the integrity check) and on any failure path; the post-DAST integrity check therefore also asserts that cleanup succeeded. Cleanup refuses to apply when the recorded profile differs from the current resolved profile unless `DAST_CLEANUP_FORCE=true`, and can be disabled entirely with `DAST_SKIP_CLEANUP=true`.
Tests:
- R025-T01: Stub `dast_baseline.py` and `dast_cleanup.py` in the fixture so each writes a sentinel file, then force the DAST lane to fail mid-run (`RUN_ZAP=true` with a failing ZAP stub) and assert both sentinels exist, proving baseline capture ran pre-failure and cleanup ran in the EXIT trap.

## Changelog

- 2026-05-10: Split former combined security lane into `07_run_static_security_tests.sh` and `23_run_dynamic_security_tests.sh`.
- 2026-05-15: Added R025/R030/R035 for ZAP proxy resilience, lane state isolation, and startup diagnostics.
- 2026-05-19: Removed macOS UI / XCUITest DAST integration (R025, R030, R035); DAST is Schemathesis + ZAP quick scan only.
- 2026-05-25: Added R025 (database-state hygiene): per-run tagging + baseline-restore cleanup with EXIT-trap safety and profile-mismatch refusal.
- 2026-05-25: Reintroduced R030 with machine-readable ZAP summary parsing and configurable severity thresholds.
- 2026-05-27: Added R035 strict Schemathesis gate with explicit downgrade toggle (`SCHEMATHESIS_FAIL_ON_FINDINGS=false`).
- 2026-05-27: Added R040 for automatic DAST Mailcart/API port collision avoidance.
- 2026-05-30: Added R045 to keep Schemathesis runtime state scoped to DAST artifact directories.
