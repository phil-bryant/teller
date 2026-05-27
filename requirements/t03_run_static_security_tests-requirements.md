# Run SAST Requirements

## Scope

Applies to:
- `tests/t03_run_static_security_tests.sh`
- `src/scripts/security/run_static_security_lane.sh`
- `src/scripts/security/common.sh`

R001  Statement: Print an explicit SAST startup banner.
Design: Emit `running SAST (Static Application Security Testing)` at script startup before scanner orchestration begins.
Tests:
- R001-T01: Run script with `RUN_SAST=false RUN_DAST=false` and verify startup output includes the exact banner string.

R005  Statement: Execute from repository root in strict shell mode.
Design: Use `set -euo pipefail`, resolve script directory from `${BASH_SOURCE[0]}`, and `cd` into that directory.
Tests:
- R005-T01: Run from a non-root working directory and verify relative paths still resolve.

R010  Statement: Bootstrap isolated security toolchain environment before scanning.
Design: Create `SECURITY_VENV_DIR` when missing, install `requirements/security/requirements-security.txt` when `semgrep` is absent in that venv, and prepend `${SECURITY_VENV_DIR}/bin` to `PATH`.
Tests:
- R010-T01: Remove `artifacts/venv/security`, run script, and verify venv creation plus tool installation path executes.

R015  Statement: Run the static security lane by default.
Design: Set `RUN_SAST=true` default and `RUN_DAST=false` default; run SAST scanners and centralized SAST gating when enabled.
Tests:
- R015-T01: Run with defaults and verify SAST reports are produced.
- R015-T02: Run with `RUN_SAST=false RUN_DAST=false` and verify script exits cleanly after setup.

R020  Statement: Emit explicit completion status and artifact location.
Design: Print lane completion markers and final success output including resolved report directory path.
Tests:
- R020-T01: Run a passing SAST lane and verify completion output includes report directory.

R025  Statement: Include Ruff lint scanning in the static security lane.
Design: Require `ruff` in the SAST toolchain, run `ruff check --output-format json .`, persist `ruff.json`, and include Ruff totals in centralized SAST summary output.
Tests:
- R025-T01: Run SAST lane and verify `ruff.json` exists in the reports directory.
- R025-T02: Run SAST lane and verify `sast-summary.json` contains `ruff_total`.

R030  Statement: Treat Ruff findings as blocking in centralized SAST gating.
Design: Count Ruff findings as high/critical equivalents for policy enforcement and fail the gate when `SECURITY_FAIL_ON_HIGH_CRITICAL=true` and Ruff findings are present.
Tests:
- R030-T01: Run SAST lane with non-empty Ruff findings and verify gate failure output.
- R030-T02: Verify `sast-summary.json` includes `ruff_high_critical` and contributes to `high_critical_total`.

R035  Statement: Secret scanners must avoid generated scanner/cache artifacts while preserving strict source scanning.
Design: Keep `detect-secrets` in the SAST lane but exclude generated paths such as `artifacts/security/reports`, `artifacts/cache/ruff`, `__pycache__`, and other runtime caches so scanner outputs do not become scanner inputs.
Tests:
- R035-T01: Run SAST lane and verify detect-secrets invocation includes `artifacts/cache/ruff` in its exclusion pattern.

R040  Statement: gitleaks must scan tracked working-tree source, not mutable runtime directories.
Design: Build a temporary snapshot of `git ls-files` from the current working tree and run `gitleaks detect --no-git` against that snapshot. This prevents feedback loops from report/cache directories while keeping modified tracked files in scope.
Tests:
- R040-T01: Run SAST lane and verify gitleaks invocation uses a temporary absolute `--source` path instead of `--source .`.

R045  Statement: Semgrep must print detailed status in unsuppressed runs.
Design: During default SAST execution (without suppression toggles), emit explicit Semgrep status output that includes detailed execution results of all findings and report artifact location.
Tests:
- R045-T01: Run SAST lane and verify output includes at least one detailed status line for each and every finding with report path details.

R047  Statement: Semgrep MUST be run WITHOUT --quiet 
Design: Make certain that Semgrep is not run with any output suppression flags
Tests:
- R047-T01: Semgrep execution command does not contain the --quiet flag.

R050  Statement: Bandit must print detailed status in unsuppressed runs.
Design: During default SAST execution (without suppression toggles), emit explicit Bandit status output that includes execution result and report artifact location.
Tests:
- R050-T01: Run SAST lane and verify output includes a `Bandit detailed status` line with report path details.

R055  Statement: pip-audit must print detailed status in unsuppressed runs.
Design: During default SAST execution (without suppression toggles), emit explicit pip-audit status output that includes execution result and report artifact location.
Tests:
- R055-T01: Run SAST lane and verify output includes a `pip-audit detailed status` line with report path details.

R060  Statement: detect-secrets must print detailed status in unsuppressed runs.
Design: During default SAST execution (without suppression toggles), emit explicit detect-secrets status output that includes execution result and report artifact location.
Tests:
- R060-T01: Run SAST lane and verify output includes a `detect-secrets detailed status` line with report path details.

R065  Statement: Ruff must print detailed status in unsuppressed runs.
Design: During default SAST execution (without suppression toggles), emit explicit Ruff status output that includes execution result and report artifact location.
Tests:
- R065-T01: Run SAST lane and verify output includes a `Ruff detailed status` line with report path details.

R070  Statement: ShellCheck must print detailed status in unsuppressed runs.
Design: During default SAST execution (without suppression toggles), emit explicit ShellCheck status output that includes execution result and report artifact location.
Tests:
- R070-T01: Run SAST lane and verify output includes a `ShellCheck detailed status` line with report path details.

R090  Statement: Financial-app policy must treat medium-or-higher security findings as blockers.
Design: Enforce conservative SAST gating so that Semgrep WARNING/ERROR/CRITICAL, Bandit MEDIUM/HIGH, ShellCheck warning/error, SwiftLint warning/error, pip-audit vulnerabilities, detect-secrets findings, Ruff findings, and gitleaks findings all contribute to a blocking total when `SECURITY_FAIL_ON_MEDIUM_OR_HIGHER=true` (default on).
Tests:
- R090-T01: Run SAST lane with Semgrep WARNING finding and verify gate fails with medium-or-higher failure output.
- R090-T02: Run SAST lane with Bandit MEDIUM finding and verify gate fails.
- R090-T03: Run SAST lane with pip-audit vulnerability present and verify gate fails.
- R090-T04: Run SAST lane with ShellCheck warning finding and verify gate fails.
- R090-T05: Run SAST lane with SwiftLint warning finding and verify gate fails.

## Changelog

- 2026-05-10: Split former combined security lane into `07_run_static_security_tests.sh` and `23_run_dynamic_security_tests.sh`.
- 2026-05-15: Added R025 to require Ruff execution and report accounting in SAST output.
- 2026-05-15: Added R030 to enforce Ruff findings as blocking SAST gate signals.
- 2026-05-15: Added R035 to exclude generated cache/report paths from detect-secrets.
- 2026-05-15: Added R040 to run gitleaks on git-tracked snapshot source and prevent report feedback loops.
- 2026-05-15: Added R045/R050/R055/R060/R065/R070 to require detailed unsuppressed status output for Semgrep, Bandit, pip-audit, detect-secrets, Ruff, and ShellCheck.
- 2026-05-15: Added R090 financial-app medium-or-higher blocking policy across SAST tools.
