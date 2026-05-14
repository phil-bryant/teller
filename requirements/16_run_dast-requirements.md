# Run DAST Requirements

## Scope

Applies to `16_run_dast.sh`.

R001  Statement: Print an explicit DAST startup banner.
Design: Emit `running DAST (Dynamic Application Security Testing)` at script startup before scanner orchestration begins.
Tests:
- Run script with `RUN_DAST=false` and verify startup output includes the exact banner string.

R005  Statement: Execute from repository root in strict shell mode.
Design: Use `set -euo pipefail`, resolve script directory from `${BASH_SOURCE[0]}`, and `cd` into that directory.
Tests:
- Run from a non-root working directory and verify relative paths still resolve.

R010  Statement: Bootstrap isolated security toolchain environment before running DAST dependencies.
Design: Create `SECURITY_VENV_DIR` when missing, install `requirements-security.txt` when `semgrep` is absent in that venv, and prepend `${SECURITY_VENV_DIR}/bin` to `PATH`.
Tests:
- Remove `.security-venv`, run script, and verify venv creation plus tool installation path executes.

R015  Statement: Run the dynamic security lane by default.
Design: Set `RUN_DAST=true` default and `RUN_SAST=false` default; run DAST scanners and DAST gate checks when enabled.
Tests:
- Run with defaults and verify DAST output includes lane completion markers.

R020  Statement: Emit explicit completion status and artifact location.
Design: Print DAST progress markers and final success output including resolved report directory path.
Tests:
- Run a passing DAST lane and verify completion output includes report directory.

## Changelog

- 2026-05-10: Split former combined security lane into `06_run_sast.sh` and `16_run_dast.sh`.
