# Run SAST Requirements

## Scope

Applies to `06_run_sast.sh`.

R001  Statement: Print an explicit SAST startup banner.
Design: Emit `running SAST (Static Application Security Testing)` at script startup before scanner orchestration begins.
Tests:
- Run script with `RUN_SAST=false RUN_DAST=false` and verify startup output includes the exact banner string.

R005  Statement: Execute from repository root in strict shell mode.
Design: Use `set -euo pipefail`, resolve script directory from `${BASH_SOURCE[0]}`, and `cd` into that directory.
Tests:
- Run from a non-root working directory and verify relative paths still resolve.

R010  Statement: Bootstrap isolated security toolchain environment before scanning.
Design: Create `SECURITY_VENV_DIR` when missing, install `requirements-security.txt` when `semgrep` is absent in that venv, and prepend `${SECURITY_VENV_DIR}/bin` to `PATH`.
Tests:
- Remove `.security-venv`, run script, and verify venv creation plus tool installation path executes.

R015  Statement: Run the static security lane by default.
Design: Set `RUN_SAST=true` default and `RUN_DAST=false` default; run SAST scanners and centralized SAST gating when enabled.
Tests:
- Run with defaults and verify SAST reports are produced.
- Run with `RUN_SAST=false RUN_DAST=false` and verify script exits cleanly after setup.

R020  Statement: Emit explicit completion status and artifact location.
Design: Print lane completion markers and final success output including resolved report directory path.
Tests:
- Run a passing SAST lane and verify completion output includes report directory.

R025  Statement: Include Ruff lint scanning in the static security lane.
Design: Require `ruff` in the SAST toolchain, run `ruff check --output-format json .`, persist `ruff.json`, and include Ruff totals in centralized SAST summary output.
Tests:
- Run SAST lane and verify `ruff.json` exists in the reports directory.
- Run SAST lane and verify `sast-summary.json` contains `ruff_total`.

R030  Statement: Treat Ruff findings as blocking in centralized SAST gating.
Design: Count Ruff findings as high/critical equivalents for policy enforcement and fail the gate when `SECURITY_FAIL_ON_HIGH_CRITICAL=true` and Ruff findings are present.
Tests:
- Run SAST lane with non-empty Ruff findings and verify gate failure output.
- Verify `sast-summary.json` includes `ruff_high_critical` and contributes to `high_critical_total`.

R035  Statement: Secret scanners must avoid generated scanner/cache artifacts while preserving strict source scanning.
Design: Keep `detect-secrets` in the SAST lane but exclude generated paths such as `.security-reports`, `.ruff_cache`, `__pycache__`, and other runtime caches so scanner outputs do not become scanner inputs.
Tests:
- Run SAST lane and verify detect-secrets invocation includes `.ruff_cache` in its exclusion pattern.

R040  Statement: gitleaks must scan tracked working-tree source, not mutable runtime directories.
Design: Build a temporary snapshot of `git ls-files` from the current working tree and run `gitleaks detect --no-git` against that snapshot. This prevents feedback loops from report/cache directories while keeping modified tracked files in scope.
Tests:
- Run SAST lane and verify gitleaks invocation uses a temporary absolute `--source` path instead of `--source .`.

## Changelog

- 2026-05-10: Split former combined security lane into `06_run_sast.sh` and `16_run_dast.sh`.
- 2026-05-15: Added R025 to require Ruff execution and report accounting in SAST output.
- 2026-05-15: Added R030 to enforce Ruff findings as blocking SAST gate signals.
- 2026-05-15: Added R035 to exclude generated cache/report paths from detect-secrets.
- 2026-05-15: Added R040 to run gitleaks on git-tracked snapshot source and prevent report feedback loops.
