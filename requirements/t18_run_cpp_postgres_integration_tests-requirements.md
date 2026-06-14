# t18 run cpp postgres integration tests Requirements

## Scope

Applies to `tests/t18_run_cpp_postgres_integration_tests.sh`, the self-contained
teller-owned lane that provisions a scratch PostgreSQL database from the
committed DDL, runs the `[postgres]`-tagged Catch2 cases against it, and drops
the database afterwards. There is no runner delegation (thick lane).

R001  Statement: Lane resolves admin credentials and skips cleanly when unavailable.
Design: `env_item_field` reads `<item>.<field>=value` lines from `~/.env`; credentials come from `TELLER_TEST_PG_ADMIN_CONNINFO` or the `LOCALHOST_POSTGRES_POSTGRES` fallback, and the lane exits 0 when no credentials or no reachable server are found.
Tests:
- R001-T01: Verify the lane resolves credentials via `env_item_field`/conninfo and skips cleanly when absent.

R005  Statement: All admin psql calls run non-interactively with strict error stops.
Design: `run_psql` invokes `psql -w -v ON_ERROR_STOP=1` with a connect timeout so failures stop immediately and never block on prompts.
Tests:
- R005-T01: Verify `run_psql` enforces `-w` and `ON_ERROR_STOP=1`.

R010  Statement: The scratch database is always dropped, even on failure.
Design: A `cleanup` function registered via `trap cleanup EXIT` drops the scratch database with `DROP DATABASE IF EXISTS ... WITH (FORCE)`.
Tests:
- R010-T01: Verify the lane registers an EXIT trap that drops the scratch database.
