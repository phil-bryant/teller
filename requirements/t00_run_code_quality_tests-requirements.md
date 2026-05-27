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
- R005-T01: Disable all tools with `RUN_VULTURE=false`, `RUN_RADON=false`, `RUN_XENON=false`, `RUN_PERIPHERY=false`, and `RUN_LIZARD=false` and verify summary/report artifacts are still written in custom report directory.

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
- R025-T01: Return sample Vulture, Radon, Xenon, Periphery, and Lizard outputs and verify each appears in console output.

R030  Statement: Run Periphery dead-code analysis on Swift sources and block by default for a financial application.
Design: Invoke `periphery scan --strict` from a configurable `PERIPHERY_PROJECT_DIR` (default `./src/macos-ui`) with `PERIPHERY_EXTRA_ARGS` (defaults: `--retain-codable-properties --retain-public --retain-objc-accessible` to suppress common SwiftUI/AppKit/Codable false positives so surfaced findings are real). Treat exit code `1` as findings; `PERIPHERY_GATE_MODE` (default `block`) controls whether findings gate the lane: `block` honors `FAIL_ON_QUALITY_ISSUES`, `warn` reports without failing for ad-hoc inspection runs. Treat other non-zero exits as execution failures. Periphery is the Swift analog of Vulture and defaults to `block` because dead code in a financial application is a real risk.
Tests:
- R030-T01: Return Periphery findings (exit `1`) with default `PERIPHERY_GATE_MODE=block` and verify the gate fails.
- R030-T02: Return Periphery findings (exit `1`) with `PERIPHERY_GATE_MODE=warn` and verify the run succeeds (findings reported but not gated).
- R030-T03: Return Periphery findings (exit `1`) with default `PERIPHERY_GATE_MODE=block` and `FAIL_ON_QUALITY_ISSUES=false` and verify the run succeeds.

R035  Statement: Run Lizard cyclomatic-complexity analysis on Swift sources and block by default for a financial application.
Design: Invoke `lizard -l swift` with configurable `LIZARD_TARGETS`, `LIZARD_CCN_THRESHOLD` (default `10`), `LIZARD_LENGTH_THRESHOLD` (default `60`), and `LIZARD_ARG_THRESHOLD` (default `5`) — industry-conventional strict thresholds appropriate for keeping audit-critical code small and obvious. Treat exit code `1` as threshold violation; `LIZARD_GATE_MODE` (default `block`) controls gating: `block` honors `FAIL_ON_QUALITY_ISSUES`, `warn` reports without failing. Treat exit code `>1` as execution failure. Lizard is the Swift analog of the Radon + Xenon combination and defaults to `block` for the same financial-risk reasons as R030.
Tests:
- R035-T01: Return Lizard threshold violation (exit `1`) with default `LIZARD_GATE_MODE=block` and verify the gate fails.
- R035-T02: Return Lizard threshold violation (exit `1`) with `LIZARD_GATE_MODE=warn` and verify the run succeeds.
- R035-T03: Return Lizard threshold violation (exit `1`) with default `LIZARD_GATE_MODE=block` and `FAIL_ON_QUALITY_ISSUES=false` and verify the run succeeds.

## Changelog

- 2026-05-26: Added initial requirements for `tests/t00_run_code_quality_tests.sh` (Vulture + Radon + Xenon lane).
- 2026-05-26: Added R025 to require console-visible quality details from tool reports.
- 2026-05-26: Added R030 (Periphery) and R035 (Lizard) to extend the quality lane with Swift dead-code and complexity analysis; expanded R005 and R025 coverage for the new tools.
- 2026-05-26: Defaulted Periphery/Lizard gating to `warn` mode (configurable via `PERIPHERY_GATE_MODE` / `LIZARD_GATE_MODE`) so the new lanes can be rolled out incrementally; tightened Periphery default args to suppress Codable/public/ObjC false positives; raised Lizard defaults to Swift-pragmatic thresholds (CCN 15, length 150, args 8).
- 2026-05-26: Flipped Periphery/Lizard gating defaults to `block` and Lizard thresholds back to strict conventional values (CCN 10, length 60, args 5) because this is a financial application; kept Periphery noise-reducing defaults so surfaced findings are real.
