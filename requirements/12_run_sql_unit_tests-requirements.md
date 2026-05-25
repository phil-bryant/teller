# Run SQL Unit Tests Requirements

## Scope

Applies to `12_run_sql_unit_tests.sh`.

R001  Statement: Run from repository root regardless of caller working directory.
Design: Resolve script directory and `cd` there before invoking the shared unit-test lane runner.
Tests:
- R001-T01: Run from a different working directory and verify the wrapper still succeeds.

R005  Statement: Execute only the SQL unit-test lane.
Design: Invoke `scripts/run_unit_test_lanes.sh` with `RUN_SQL_TESTS=true` and all other unit lanes disabled.
Tests:
- R005-T01: Verify the wrapper exports lane toggles with only SQL tests enabled.
