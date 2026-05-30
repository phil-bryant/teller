# Run Unit Test Lanes Helper Requirements

## Scope

Applies to `src/scripts/run_unit_test_lanes.sh`.

R001  Statement: Run all enabled unit-test lanes from repository root with strict shell behavior.
Design: Resolve repository root from script location, enter that directory, and use fail-fast shell settings while honoring lane toggle environment variables.
Tests:
- R001-T01: Verify the helper re-roots execution and respects lane toggles for shell/python/sql/swift execution.

R005  Statement: Resolve DB profile exports before SQL-lane execution and fail fast on profile/preflight gaps.
Design: Require executable `db_profile_export.sh`, evaluate profile exports, and run target-specific SQL-lane preflight (`pg_prove` + pgtap for PostgreSQL-family targets, sqlite preflight/tooling for SQLite target), stopping immediately on prerequisite gaps.
Tests:
- R005-T01: Verify SQL preflight failures surface clear diagnostics and block SQL test execution.

R010  Statement: Run Swift tests under shared SwiftPM locking with bounded stale-cache recovery.
Design: Source `macos_ui_swift_lock.sh`, execute `swift test` under lock, and retry exactly once after clearing `.build` only for stale-checkout style access failures.
Tests:
- R010-T01: Verify lock helper invocation and single-retry stale-cache recovery path behavior.

R015  Statement: Stop lane execution when enabled Python/SQL/Swift test suites fail.
Design: Propagate non-zero status from each enabled lane and exit immediately on lane failure.
Tests:
- R015-T01: Verify helper exits non-zero when an enabled lane command returns failure.

R020  Statement: Perform stale-cache retry only for recognized Swift checkout-access failures.
Design: Trigger one retry after clearing `.build` only when output indicates stale checkout access errors; do not retry unrelated failures.
Tests:
- R020-T01: Verify stale-checkout signal triggers single retry and unrelated failures do not.
- R020-T02: Verify sandbox-denied Swift test startup is treated as a graceful skip path instead of a stale-cache retry loop.

R025  Statement: Resolve DB profile exports before SQL lane preflight and execution.
Design: Require executable `db_profile_export.sh`, evaluate exported variables, and use profile-derived backend settings (PostgreSQL or SQLite) for SQL preflight checks.
Tests:
- R025-T01: Verify missing or failing DB profile export helper prevents SQL lane startup.

R030  Statement: Keep crash-verification flow isolated from shared unit-test lanes.
Design: Do not invoke crash verification from this helper; keep crash checks in dedicated numbered entrypoint.
Tests:
- R030-T01: Verify helper does not call crash-verification script when running default lanes.

R035  Statement: Refuse SQL lane execution when DB profile setup cannot be resolved.
Design: Fail fast when DB profile helper execution fails and emit explicit setup diagnostics.
Tests:
- R035-T01: Verify SQL lane preflight exits with setup diagnostic when profile exports fail.

R038  Statement: Keep Hypothesis and other Python tool caches out of the repository root.
Design: Source `export_test_cache_env.sh` at startup and default `HYPOTHESIS_STORAGE_DIRECTORY` to `${CACHE_ROOT}/hypothesis` under `artifacts/cache/`.
Tests:
- R038-T01: Verify the helper exports `HYPOTHESIS_STORAGE_DIRECTORY` ending in `artifacts/cache/hypothesis`.
