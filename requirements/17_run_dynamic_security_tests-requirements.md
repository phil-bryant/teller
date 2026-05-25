# Run DAST Requirements

## Scope

Applies to `17_run_dynamic_security_tests.sh`.

R001  Statement: Print an explicit DAST startup banner.
Design: Emit `running DAST (Dynamic Application Security Testing)` at script startup before scanner orchestration begins.
Tests:
- R001-T01: Run script with `RUN_DAST=false` and verify startup output includes the exact banner string.

R005  Statement: Execute from repository root in strict shell mode.
Design: Use `set -euo pipefail`, resolve script directory from `${BASH_SOURCE[0]}`, and `cd` into that directory.
Tests:
- R005-T01: Run from a non-root working directory and verify relative paths still resolve.

R010  Statement: Bootstrap isolated security toolchain environment before running DAST dependencies.
Design: Create `SECURITY_VENV_DIR` when missing, install `requirements-security.txt` when `semgrep` is absent in that venv, and prepend `${SECURITY_VENV_DIR}/bin` to `PATH`.
Tests:
- R010-T01: Remove `.security-venv`, run script, and verify venv creation plus tool installation path executes.

R015  Statement: Run the dynamic security lane by default.
Design: Set `RUN_DAST=true` default and `RUN_SAST=false` default; run DAST scanners and DAST gate checks when enabled.
Tests:
- R015-T01: Run with defaults and verify DAST output includes lane completion markers.

R020  Statement: Emit explicit completion status and artifact location.
Design: Print DAST progress markers and final success output including resolved report directory path.
Tests:
- R020-T01: Run a passing DAST lane and verify completion output includes report directory.

## Changelog

- 2026-05-10: Split former combined security lane into `06_run_static_security_tests.sh` and `17_run_dynamic_security_tests.sh`.
- 2026-05-15: Added R025/R030/R035 for ZAP proxy resilience, lane state isolation, and startup diagnostics.
- 2026-05-19: Removed macOS UI / XCUITest DAST integration (R025, R030, R035); DAST is Schemathesis + ZAP quick scan only.
