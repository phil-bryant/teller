-- One-shot cleanup of historical DAST orphans accumulated before the
-- per-run baseline + cleanup hygiene (R025 in
-- requirements/22_run_dynamic_security_tests-requirements.md) was added.
-- #R001: Remove only legacy DAST artifacts matched by conservative fingerprints.
-- #R005: Execute deletes in FK-safe order inside an explicit transaction.
-- #R010: Print pre-delete row-count previews for operator visibility.
--
-- Run manually once against the affected profile, e.g.:
--   psql "$(./src/scripts/db_profile_export.sh local | grep ^URL= | cut -d= -f2-)" \
--     -f src/scripts/cleanup_legacy_dast_artifacts.sql
--
-- The script is conservative: it only deletes rows that match the
-- predictable seeder fingerprints emitted by 22_run_dynamic_security_tests.sh
-- (level_1='DAST' for categories, schemathesis-seed-*/dast-seed-* emails
-- for matches). Non-DAST data is untouched. Wrap in a transaction so the
-- entire delete is atomic and easy to abort with ROLLBACK.

BEGIN;

-- Surface what is about to be removed for the operator.
WITH category_targets AS (
    SELECT nys_snw_category_id
      FROM teller.nys_snw_category
     WHERE is_seed = FALSE
       AND level_1 = 'DAST'
       AND level_1_name IN ('DAST Seed', 'DAST Contract')
)
SELECT 'nys_snw_category orphans (non-seed DAST rows)' AS what,
       COUNT(*)                                       AS row_count
  FROM category_targets;

SELECT 'transaction_nys_snw_category mappings pointing at DAST orphans' AS what,
       COUNT(*) AS row_count
  FROM teller.transaction_nys_snw_category t
  JOIN teller.nys_snw_category c
    ON c.nys_snw_category_id = t.nys_snw_category_id
 WHERE c.is_seed = FALSE
   AND c.level_1 = 'DAST'
   AND c.level_1_name IN ('DAST Seed', 'DAST Contract');

SELECT 'transaction_email_match seeder rows' AS what,
       COUNT(*) AS row_count
  FROM teller.transaction_email_match
 WHERE email_message_id LIKE 'schemathesis-seed-%@example.invalid'
    OR email_message_id LIKE 'dast-seed-%@example.invalid';

-- Drop classifications that reference DAST orphan categories first so the
-- subsequent category delete is FK-safe.
DELETE FROM teller.transaction_nys_snw_category t
 USING teller.nys_snw_category c
 WHERE c.nys_snw_category_id = t.nys_snw_category_id
   AND c.is_seed = FALSE
   AND c.level_1 = 'DAST'
   AND c.level_1_name IN ('DAST Seed', 'DAST Contract');

DELETE FROM teller.nys_snw_category
 WHERE is_seed = FALSE
   AND level_1 = 'DAST'
   AND level_1_name IN ('DAST Seed', 'DAST Contract');

-- Audit rows cascade via the transaction_email_match FK ON DELETE CASCADE.
DELETE FROM teller.transaction_email_match
 WHERE email_message_id LIKE 'schemathesis-seed-%@example.invalid'
    OR email_message_id LIKE 'dast-seed-%@example.invalid';

-- Inspect the result before committing. Re-run with COMMIT vs ROLLBACK as
-- needed; default behaviour is to commit on script completion.
COMMIT;
