# DAST Cleanup Restore Requirements

## Scope

Applies to `src/scripts/dast_cleanup.py`.

R001  Statement: Restore baseline-captured database state in one transactional cleanup sequence.
Design: Restore baseline mutable rows, delete post-baseline inserts, reconcile classifications/categories, and persist operation counts in a summary artifact. Classification reconciliation must use bound SQL parameters (for example `transaction_id = ANY(:baseline_tx_ids)`) instead of dynamic SQL interpolation.
Tests:
- R001-T01: Verify cleanup applies expected delete/restore sequence and writes count metadata on success.

R005  Statement: Refuse unsafe cleanup when baseline profile mismatches active profile.
Design: Compare baseline and active profile names, return `refused` unless `DAST_CLEANUP_FORCE=true`, and emit refusal diagnostics in summary output.
Tests:
- R005-T01: Verify profile mismatch returns non-zero refusal without mutating data unless force override is enabled.

R010  Statement: Handle missing/non-captured baselines as non-fatal skips with diagnostics.
Design: When baseline is missing or not `captured`, write `status=skipped` summary output with explicit reason and exit zero.
Tests:
- R010-T01: Verify missing and skipped-status baselines produce non-fatal summaries with actionable error messages.

## Changelog

- 2026-05-25: Clarified R001 to require bound-parameter SQL for classification reconciliation deletes.
