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

R350  Statement: Load DAST baseline file payload.
Design: Read and validate baseline JSON input payloads.
Tests:
- R350-T01: Verify baseline loader helper is available for cleanup startup.

R351  Statement: Write cleanup summary payload file.
Design: Persist cleanup summary JSON payload to disk.
Tests:
- R351-T01: Verify summary writer helper is available for reporting.

R352  Statement: Emit cleanup summary and return exit code.
Design: Emit summary payload and return mapped exit status.
Tests:
- R352-T01: Verify summary emitter helper is available for final return policy.

R353  Statement: Skip cleanup with recorded error payload.
Design: Return skipped summary for recoverable cleanup conditions.
Tests:
- R353-T01: Verify skip-with-error helper is available for skip flows.

R354  Statement: Refuse cleanup with recorded error payload.
Design: Return refused summary for unsafe cleanup conditions.
Tests:
- R354-T01: Verify refuse-with-error helper is available for refusal flows.

R355  Statement: Restore baseline transaction email matches.
Design: Restore baseline match rows before post-baseline cleanup.
Tests:
- R355-T01: Verify restore-matches helper is available for restoration path.

R356  Statement: Delete post-baseline match audit rows.
Design: Delete audit rows newer than baseline watermark.
Tests:
- R356-T01: Verify delete-audits helper is available for cleanup path.

R357  Statement: Delete post-baseline transaction matches.
Design: Delete match rows newer than baseline watermark.
Tests:
- R357-T01: Verify delete-matches helper is available for cleanup path.

R358  Statement: Reconcile classifications to baseline state.
Design: Reconcile classification rows to baseline transaction set.
Tests:
- R358-T01: Verify classification reconciliation helper is available.

R359  Statement: Delete post-baseline category rows.
Design: Delete categories newer than baseline watermark.
Tests:
- R359-T01: Verify delete-categories helper is available for cleanup path.

R360  Statement: Restore baseline categories.
Design: Restore baseline category rows after cleanup deletion.
Tests:
- R360-T01: Verify restore-categories helper is available for restoration path.

R361  Statement: Build profile-mismatch refusal message text.
Design: Construct refusal diagnostics for profile mismatch conditions.
Tests:
- R361-T01: Verify profile-refusal message helper is available for refusal diagnostics.

R362  Statement: Run cleanup transaction sequence.
Design: Execute full cleanup transactional operation sequence.
Tests:
- R362-T01: Verify cleanup transaction helper is available for orchestration.

R363  Statement: Orchestrate cleanup run and exit policy.
Design: Run cleanup workflow and emit final summary/exit code.
Tests:
- R363-T01: Verify cleanup main entrypoint is available for orchestration.
