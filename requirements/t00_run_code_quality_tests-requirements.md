# Run Code Quality Checks Requirements

## Scope

Applies to `tests/t00_run_code_quality_tests.sh`.

R001  Statement: Run in strict shell mode from repository root.
Design: Use `set -euo pipefail`, resolve script path from `${BASH_SOURCE[0]}`, and `cd` into repo root before running any tool.
Tests:
- R001-T01: Run from a non-root working directory and verify relative paths resolve under repo root.

R005  Statement: Support configurable report destination, targets, and quality gate behavior.
Design: Read `QUALITY_REPORT_DIR`, `QUALITY_TARGETS`, `FAIL_ON_QUALITY_ISSUES`, and per-tool `RUN_*` flags from environment with safe defaults; always create report directory before writing outputs.
Tests:
- R005-T01: Disable all tools with `RUN_VULTURE=false`, `RUN_RADON=false`, and `RUN_XENON=false` and verify summary/report artifacts are still written in custom report directory.

R010  Statement: Run Vulture dead-code checks and gate findings based on policy.
Design: Invoke `vulture` with configurable `VULTURE_MIN_CONFIDENCE`; treat exit code `1` or `3` as findings and gate failure only when `FAIL_ON_QUALITY_ISSUES=true`; treat other non-zero exits as execution failures.
Tests:
- R010-T01: Return Vulture findings (exit `1`) and verify default gate fails.
- R010-T02: Return Vulture findings (exit `1`) with `FAIL_ON_QUALITY_ISSUES=false` and verify run succeeds.
- R010-T03: Return Vulture execution failure (exit `2`) and verify script fails with execution error message.
- R010-T04: Return Vulture findings (exit `3`) and verify findings are gated (not treated as execution failure).

R015  Statement: Run Radon complexity analysis and emit report artifacts.
Design: Invoke `radon cc` with summary/details flags and configured exclusions, write `radon.txt`, and surface execution status in output.
Tests:
- R015-T01: Run with Radon stub and verify invocation includes configured exclude argument and report output is produced.

R020  Statement: Run Xenon threshold enforcement and apply quality gate policy.
Design: Invoke `xenon` with configurable `--max-absolute`, `--max-modules`, and `--max-average` thresholds; treat exit code `1` as threshold violation and gate based on `FAIL_ON_QUALITY_ISSUES`; treat exit code `>1` as execution failure.
Tests:
- R020-T01: Return Xenon threshold violation (exit `1`) and verify default gate fails.
- R020-T02: Return Xenon threshold violation (exit `1`) with `FAIL_ON_QUALITY_ISSUES=false` and verify run succeeds.

R025  Statement: Print actionable tool details directly to console output.
Design: After each tool run, print non-empty report details to stdout (bounded excerpt) so operators can review findings and metrics without opening report files.
Tests:
- R025-T01: Return sample Vulture, Radon, and Xenon outputs and verify each appears in console output.

## Changelog

- 2026-05-26: Added initial requirements for `tests/t00_run_code_quality_tests.sh` (Vulture + Radon + Xenon lane).
- 2026-05-26: Added R025 to require console-visible quality details from tool reports.
