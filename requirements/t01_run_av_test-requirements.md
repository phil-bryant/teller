# Run AV Checks Requirements

## Scope

Applies to `tests/t01_run_av_test.sh`.

R001  Statement: Run in strict shell mode and execute from repository root.
Design: Use `set -euo pipefail`, resolve script directory from `${BASH_SOURCE[0]}`, and `cd` into that directory.
Tests:
- R001-T01: Run from a non-root working directory and verify relative paths still resolve.

R005  Statement: Support configurable AV report destination and policy flags.
Design: Resolve `SECURITY_REPORT_DIR`, `RUN_CLAMAV`, and `AV_FAIL_ON_INFECTED` from environment with safe defaults; always create the report directory before writing artifacts.
Tests:
- R005-T01: Set `RUN_CLAMAV=false` and verify script exits cleanly with skipped summary artifacts.

R010  Statement: Run ClamAV repository malware scans and persist machine-readable artifacts.
Design: When `RUN_CLAMAV=true`, require `clamscan`, run a recursive repository scan, and persist `clamav.log` and `clamav-summary.json`.
Tests:
- R010-T01: Run AV lane with clean ClamAV output and verify `clamav.log` and `clamav-summary.json` are produced.

R015  Statement: Print signature freshness metadata and resolved scan target context.
Design: Before scan execution, print signature DB freshness metadata (latest file timestamp/age/status) and the fully resolved scan target path; default staleness threshold is 24 hours via `CLAMAV_SIGNATURE_MAX_AGE_HOURS`.
Tests:
- R015-T01: Run with a valid scan target and verify output includes freshness metadata and resolved target path.

R020  Statement: Emit periodic heartbeat lines during long-running scans.
Design: While ClamAV runs, print in-progress heartbeat updates using configurable heartbeat/poll intervals.
Tests:
- R020-T01: Run with a slow ClamAV stub and verify at least one in-progress heartbeat line is printed.

R025  Statement: Enforce strict signature refresh and retry once when DB files are missing.
Design: If signature freshness is stale, proactively run `freshclam --stdout` before the first scan (bootstrapping Homebrew config when needed). When ClamAV reports `No supported database files found`, retry the scan once after refresh; if a proactive refresh already ran, retry once without issuing a redundant second refresh.
Tests:
- R025-T01: Stub missing DB on first scan and verify `freshclam --stdout` runs and scan retries once.
- R025-T02: Stub stale signatures and verify `freshclam --stdout` runs before `clamscan`.

R030  Statement: Delimit AV tool execution with bounded headers including purpose and URL.
Design: Before ClamAV invocation, print a boxed ASCII header containing tool name, two explainer lines, and official tool URL.
Tests:
- R030-T01: Run AV lane and verify output includes box border, ClamAV tool name, and URL.

R035  Statement: Enforce AV gate behavior and explicit completion status.
Design: Treat ClamAV exit code `1` as findings (not execution failure), fail when `AV_FAIL_ON_INFECTED=true` and infected count is non-zero, and print explicit completion line with report directory on success.
Tests:
- R035-T01: Stub ClamAV to return exit code `1` with infected files and verify AV gate failure by default.
- R035-T02: Set `AV_FAIL_ON_INFECTED=false` and verify infected findings do not fail the run.
- R035-T03: Verify completion output includes the report directory path on success.

## Changelog

- 2026-05-09: Added standalone AV lane requirements for `06_run_av_test.sh` after splitting ClamAV out of `15_run_security_checks.sh`.
