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
