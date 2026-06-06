# Compare Postgres SQLite Requirements

## Scope

Applies to `tools/compare_postgres_sqlite.py`.

R001  Statement: Resolve explicit postgres/sqlite DB profiles and connect to both engines.
Design: Support `--postgres-profile` and `--sqlite-profile`; fail clearly when profile resolution or connection fails.
Tests:
- R001-T01: Run script with default profiles and verify both connections are attempted (`tests/py/test_compare_postgres_sqlite.py`).

R005  Statement: Compare table and column coverage between engines before row diffing.
Design: Enumerate table names in postgres schema and sqlite attached database, then verify each shared table has identical ordered column names.
Tests:
- R005-T01: Introduce a table/column drift and verify the script reports it as a mismatch (`tests/py/test_compare_postgres_sqlite.py`).

R010  Statement: Compare every row and column value for all shared tables.
Design: Read full table rows from each engine and compare normalized row multisets so duplicates are counted correctly.
Tests:
- R010-T01: Modify one row value in either engine and verify the table is flagged with row mismatch details (`tests/py/test_compare_postgres_sqlite.py`).

R015  Statement: Emit machine-readable mismatch output and fail the process on divergence.
Design: Write a JSON report via `--output-json`, print concise mismatch lines, return exit code `1` on differences and `0` on exact parity.
Tests:
- R015-T01: Run identical databases and verify exit `0`; run with drift and verify exit `1` plus report output (`tests/py/test_compare_postgres_sqlite.py`).

R600  Statement: Discover the repository root deterministically from script location.
Design: Walk parent directories from script path until the repository marker layout is found.
Tests:
- R600-T01: Resolve repository root from nested script path fixture (`tests/py/test_compare_postgres_sqlite.py`).

R605  Statement: Resolve named DB profiles to concrete connection settings.
Design: Temporarily set `TELLER_DB_PROFILE`, clear resolver cache, resolve profile, and restore prior env/cache state.
Tests:
- R605-T01: Resolve named profile while restoring env/cache state (`tests/py/test_compare_postgres_sqlite.py`).

R610  Statement: Open PostgreSQL connections from resolved profile settings.
Design: Build connect args from resolved profile and configure search path/runtime role on connection startup.
Tests:
- R610-T01: Build postgres connection args and execute session setup statements (`tests/py/test_compare_postgres_sqlite.py`).

R615  Statement: Open SQLite SQLCipher connections from resolved profile settings.
Design: Validate sqlite path/key, initialize SQLCipher key, and attach encrypted sqlite database.
Tests:
- R615-T01: Attach sqlite database using resolved SQLCipher key and path (`tests/py/test_compare_postgres_sqlite.py`).

R620  Statement: Enumerate table names for each engine.
Design: Resolve postgres schema then query postgres/sqlite catalogs for ordered table names.
Tests:
- R620-T01: Enumerate postgres schema and sqlite table names through helper queries (`tests/py/test_compare_postgres_sqlite.py`).

R625  Statement: Enumerate ordered column names for shared tables.
Design: Query information_schema/PRAGMA metadata and return deterministic column ordering.
Tests:
- R625-T01: Enumerate ordered postgres and sqlite column names for a table (`tests/py/test_compare_postgres_sqlite.py`).

R630  Statement: Safely quote engine identifiers when building SQL.
Design: Escape embedded quotes and wrap identifiers in double quotes for both engines.
Tests:
- R630-T01: Quote identifiers containing embedded quotes safely (`tests/py/test_compare_postgres_sqlite.py`).

R635  Statement: Fetch row multisets per table from each engine.
Design: Project selected columns and canonicalize fetched rows into row-counter multisets.
Tests:
- R635-T01: Fetch postgres/sqlite rows and route results through row-counter helper (`tests/py/test_compare_postgres_sqlite.py`).

R640  Statement: Report per-engine row counts for shared tables.
Design: Execute row-count queries and coerce returned counts to integers.
Tests:
- R640-T01: Execute row-count helpers and coerce integer results (`tests/py/test_compare_postgres_sqlite.py`).

R645  Statement: Canonicalize values for stable cross-engine equality checks.
Design: Normalize decimals/date-like values and apply context-aware canonicalization for table/column-specific rules.
Tests:
- R645-T01: Canonicalize decimal/date/context-aware values into stable comparison tuples (`tests/py/test_compare_postgres_sqlite.py`).

R650  Statement: Canonicalize monetary values into a unified representation.
Design: Convert postgres decimal dollars and sqlite integer cents to equivalent cent-based canonical values.
Tests:
- R650-T01: Canonicalize equivalent postgres/sqlite money values to matching cents (`tests/py/test_compare_postgres_sqlite.py`).

R655  Statement: Normalize audit payload JSON and strip volatile timestamp fields.
Design: Remove created/updated timestamp keys and normalize nested audit payload values before comparison.
Tests:
- R655-T01: Normalize audit payload data and strip volatile timestamp keys recursively (`tests/py/test_compare_postgres_sqlite.py`).

R660  Statement: Build order-independent row multisets preserving duplicate counts.
Design: Canonicalize each row and count rows in a multiset so ordering does not affect parity checks.
Tests:
- R660-T01: Produce equivalent counters for reordered rows while preserving duplicate counts (`tests/py/test_compare_postgres_sqlite.py`).

R665  Statement: Format bounded counter-example output for mismatched rows.
Design: Return at most the requested number of most-common mismatched rows with count and row payload.
Tests:
- R665-T01: Truncate counter-example output to requested limit while preserving count/row fields (`tests/py/test_compare_postgres_sqlite.py`).
