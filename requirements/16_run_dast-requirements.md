# Run DAST Requirements

## Scope

Applies to `16_run_dast.sh`.

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

R025  Statement: Keep macOS UI DAST proxy startup resilient under port contention.
Design: Before launching ZAP daemon for macOS UI DAST, validate the requested localhost proxy port and automatically pick the next available port when the requested port is already in use.
Tests:
- R025-T01: Occupy the requested proxy port and verify the runner auto-selects a free fallback port.
- R025-T02: Set a non-numeric proxy port and verify startup fails with a clear validation error.

R030  Statement: Isolate OWASP ZAP home state across quick-scan and daemon lanes.
Design: Use separate ZAP home directories for quick scan and macOS UI daemon startup (while allowing explicit environment overrides) to avoid shared-state startup coupling.
Tests:
- R030-T01: Run with defaults and verify quick-scan and daemon invocations use distinct ZAP home paths.

R035  Statement: Surface actionable diagnostics when ZAP daemon startup fails.
Design: If the macOS UI ZAP daemon cannot become healthy in time, fail fast and print daemon startup log tail so bind/address issues are visible in lane output.
Tests:
- R035-T01: Stub daemon startup timeout and verify output includes failure context plus log tail marker.

## Changelog

- 2026-05-10: Split former combined security lane into `06_run_sast.sh` and `16_run_dast.sh`.
- 2026-05-15: Added R025/R030/R035 for ZAP proxy resilience, lane state isolation, and startup diagnostics.
