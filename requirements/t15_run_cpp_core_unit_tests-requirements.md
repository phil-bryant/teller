# t15 run cpp core unit tests Requirements

## Scope

Applies to `tests/t15_run_cpp_core_unit_tests.sh`, the self-contained teller-owned
C++ core lane that builds `tellercore` and runs its Catch2 unit suite. There is
no runner delegation: the C++ core is teller-owned, so this is a thick lane.

R001  Statement: Lane configures and builds the teller C++ core in RelWithDebInfo.
Design: Run `cmake -S src/core -B src/core/build -DCMAKE_BUILD_TYPE=RelWithDebInfo` then `cmake --build` with host parallelism.
Tests:
- R001-T01: Verify the lane configures (RelWithDebInfo) and builds the C++ core.

R005  Statement: Lane runs the Catch2 C++ core unit suite.
Design: Execute the built `tellercore_tests` binary; PostgreSQL-tagged cases skip unless `TELLER_TEST_PG_CONNINFO` is set (covered by t18).
Tests:
- R005-T01: Verify the lane runs `tellercore_tests` and reports a passing marker.
