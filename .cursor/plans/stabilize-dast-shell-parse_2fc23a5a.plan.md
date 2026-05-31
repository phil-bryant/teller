---
name: stabilize-dast-shell-parse
overview: Harden the DAST lane scripts against environment-dependent shell parsing so `tests/t12_run_dynamic_security_tests.sh` finishes cleanly after successful scans.
todos:
  - id: refactor-run-dast-checks-function
    content: Convert run_dast_checks to brace-based function syntax in src/scripts/security/run_dynamic_security_lane.sh while preserving behavior
    status: completed
  - id: harden-wrapper-interpreter
    content: Change tests/t12_run_dynamic_security_tests.sh to exec bash for deterministic interpreter selection
    status: completed
  - id: verify-no-parse-regression
    content: Run bash syntax checks and re-run dynamic security test wrapper to confirm issue is resolved
    status: completed
isProject: false
---

# Stabilize DAST Shell Parsing

## Goal
Eliminate the post-run shell parse failure (`syntax error near unexpected token '('`) in the dynamic security test entrypoint while preserving current DAST/SAST behavior.

## Findings from quick research
- The failure is reported at the tail of [`src/scripts/security/run_dynamic_security_lane.sh`](src/scripts/security/run_dynamic_security_lane.sh), after DAST work has already completed.
- Current script parses cleanly with Bash syntax checking, so the crash is likely environment-sensitive parsing rather than a deterministic logic failure.
- [`src/scripts/security/run_dynamic_security_lane.sh`](src/scripts/security/run_dynamic_security_lane.sh) uses a Bash-specific subshell function form (`name() (`) for `run_dast_checks`, which is a common compatibility tripwire when execution context slips away from strict Bash.
- [`tests/t12_run_dynamic_security_tests.sh`](tests/t12_run_dynamic_security_tests.sh) delegates by `exec`-ing the lane script directly, which depends on shebang resolution and environment behavior.

## Planned changes
- Update [`src/scripts/security/run_dynamic_security_lane.sh`](src/scripts/security/run_dynamic_security_lane.sh):
  - Refactor `run_dast_checks` from Bash subshell function syntax (`run_dast_checks() (` ... `)`) to standard brace function syntax (`run_dast_checks() {` ... `}`) while preserving existing cleanup and error semantics.
  - Keep the same variable scoping behavior by making `local` usage explicit where needed.
- Update [`tests/t12_run_dynamic_security_tests.sh`](tests/t12_run_dynamic_security_tests.sh):
  - Invoke the lane script via explicit `bash` (`exec bash ...`) so wrapper execution cannot drift into a shell that rejects Bash-only grammar.

## Validation plan
- Run `bash -n` on both scripts after edits.
- Re-run [`tests/t12_run_dynamic_security_tests.sh`](tests/t12_run_dynamic_security_tests.sh) to confirm no parse error appears after completion.
- Confirm end-of-run output includes the final success/footer line from the lane script and no trailing shell syntax diagnostics.