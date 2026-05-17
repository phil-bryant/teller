# Run AV Checks Requirements

## Scope

Applies to `05_run_av_checks.sh`.

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
Design: Before scan execution, print signature DB freshness metadata (latest file timestamp/age) and the fully resolved scan target path.
Tests:
- R015-T01: Run with a valid scan target and verify output includes freshness metadata and resolved target path.

R020  Statement: Emit periodic heartbeat lines during long-running scans.
Design: While ClamAV runs, print in-progress heartbeat updates using configurable heartbeat/poll intervals.
Tests:
- R020-T01: Run with a slow ClamAV stub and verify at least one in-progress heartbeat line is printed.

R025  Statement: Retry once after signature refresh when ClamAV DB files are missing.
Design: When ClamAV reports `No supported database files found`, attempt one-time `freshclam --stdout` refresh (bootstrapping Homebrew config when needed), then retry scan once.
Tests:
- R025-T01: Stub missing DB on first scan and verify `freshclam --stdout` runs and scan retries once.

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

- 2026-05-09: Added standalone AV lane requirements for `05_run_av_checks.sh` after splitting ClamAV out of `14_run_security_checks.sh`.
