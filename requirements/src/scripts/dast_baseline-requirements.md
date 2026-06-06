# DAST Baseline Snapshot Requirements

## Scope

Applies to `src/scripts/dast_baseline.py`.

R001  Statement: Capture a baseline snapshot of mutable DAST-affected database tables.
Design: Record baseline maxima and full mutable-row snapshots for `nys_snw_category`, `transaction_email_match`, and `transaction_nys_snw_category` with profile metadata.
Tests:
- R001-T01: Verify baseline payload structure includes profile details, maxima, and table snapshot arrays.

R005  Statement: Degrade safely when database dependencies are unavailable.
Design: On import/setup failure, write a `status=skipped` payload with reason metadata instead of failing hard.
Tests:
- R005-T01: Simulate database import failure and verify skipped payload generation with explanatory reason text.

R010  Statement: Emit operator-readable baseline summary output.
Design: Print concise JSON summary with captured counts and output path after successful snapshot write.
Tests:
- R010-T01: Verify successful run emits summary JSON including status, profile, and table count fields.

R345  Statement: Serialize values to ISO form for baseline payloads.
Design: Convert datetime-like values to ISO strings for JSON output.
Tests:
- R345-T01: Verify _iso helper is available for baseline serialization.

R346  Statement: Serialize DB rows to column-keyed dict payloads.
Design: Map row tuples and column names into JSON-ready dictionaries.
Tests:
- R346-T01: Verify _serialize_row helper is available for row serialization.

R347  Statement: Capture DAST baseline snapshot orchestrator behavior.
Design: Run baseline capture flow and persist baseline snapshot artifacts.
Tests:
- R347-T01: Verify baseline main entrypoint is available for orchestration.
