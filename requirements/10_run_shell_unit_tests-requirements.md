# Run Shell Unit Tests Requirements

## Scope

Applies to `10_run_shell_unit_tests.sh`.

## Ownership Boundaries

This document owns wrapper behavior only.
Shared lane implementation details are owned by:
- `requirements/src/scripts/run_unit_test_lanes-requirements.md`

R001  Statement: Run from repository root regardless of caller working directory.
Design: Resolve script directory and `cd` there before invoking the shared unit-test lane runner.
Tests:
- R001-T01: Run from a different working directory and verify the wrapper still succeeds.

R005  Statement: Execute only the shell unit-test lane.
Design: Invoke `src/scripts/run_unit_test_lanes.sh` with `RUN_SHELL_TESTS=true` and all other unit lanes disabled.
Tests:
- R005-T01: Verify the wrapper exports lane toggles with only shell tests enabled.

R006  Statement: Print a clear end-of-run status marker.
Design: Emit a final line with `✅` on success and `❌` on failure after the shell unit-test lane invocation completes.
Tests:
- R006-T01: When the shared lane runner exits `0`, verify wrapper output ends with `✅`.
- R006-T02: When the shared lane runner exits non-zero, verify wrapper output ends with `❌` and wrapper exits non-zero.
