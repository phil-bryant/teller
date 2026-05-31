# Verify FileVault Encryption Requirements

## Scope

Applies to `tests/t18_verify_filevault_encryption_test.sh`.

R001  Statement: Run in strict shell mode and execute from repository root.
Design: Use `set -euo pipefail`, resolve script directory from `${BASH_SOURCE[0]}`, and `cd` into repository root.
Tests:
- R001-T01: Run from a non-root working directory and verify the script exits successfully when FileVault is enabled.

R005  Statement: Enforce FileVault encryption on the boot volume.
Design: Invoke the configured FileVault status command (default `fdesetup status`) and pass only when output contains `FileVault is On.`; otherwise fail with the reported status.
Tests:
- R005-T01: Stub enabled FileVault status output and verify the script exits successfully.
- R005-T02: Stub disabled FileVault status output and verify the script exits with failure.

R010  Statement: Require macOS for FileVault verification.
Design: Fail fast when `uname -s` is not `Darwin` because FileVault is a macOS-only control.
Tests:
- R010-T01: Stub non-Darwin platform detection and verify the script exits with failure.

R015  Statement: Require FileVault status tooling before enforcement.
Design: When using the default `fdesetup status` command, require `fdesetup` on `PATH`; fail clearly when the status command exits non-zero.
Tests:
- R015-T01: Stub a failing FileVault status command and verify the script exits with failure.
