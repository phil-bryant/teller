-- pgTAP: nys_snw_category seed protection and integrity invariants.
BEGIN;

SELECT plan(9);

SELECT has_column('classy', 'nys_snw_category', 'is_seed', 'is_seed provenance column exists');
SELECT col_not_null('classy', 'nys_snw_category', 'is_seed', 'is_seed is non-nullable');
SELECT ok(
  EXISTS (
    SELECT 1
      FROM pg_constraint
     WHERE conname = 'nys_snw_category_non_empty_hierarchy_chk'
  ),
  'non-empty hierarchy check exists'
);
SELECT ok(
  EXISTS (
    SELECT 1
      FROM pg_constraint
     WHERE conname = 'nys_snw_category_no_control_chars_chk'
  ),
  'control-character check exists'
);
SELECT has_function('classy', 'prevent_seed_category_mutation', ARRAY[]::text[], 'seed-guard trigger function exists');
SELECT has_trigger('classy', 'nys_snw_category', 'nys_snw_category_seed_guard_trg', 'seed-guard trigger exists');

SELECT throws_like(
  $$
    UPDATE classy.nys_snw_category
       SET categorization = 'Mutated by test'
     WHERE nys_snw_category_id = (SELECT MIN(nys_snw_category_id) FROM classy.nys_snw_category WHERE is_seed = TRUE)
  $$,
  '%immutable%',
  'seed rows reject UPDATE'
);

SELECT throws_like(
  $$
    DELETE FROM classy.nys_snw_category
     WHERE nys_snw_category_id = (SELECT MIN(nys_snw_category_id) FROM classy.nys_snw_category WHERE is_seed = TRUE)
  $$,
  '%cannot be deleted%',
  'seed rows reject DELETE'
);

SELECT lives_ok(
  $$
    DO $do$
    DECLARE
      category_id BIGINT;
    BEGIN
      INSERT INTO classy.nys_snw_category (level_1_name, categorization, applicability)
      VALUES ('TEST EXPENSES', 'Test Category', 'N/A')
      RETURNING nys_snw_category_id INTO category_id;

      UPDATE classy.nys_snw_category
         SET categorization = 'Test Category Updated'
       WHERE nys_snw_category_id = category_id;

      DELETE FROM classy.nys_snw_category
       WHERE nys_snw_category_id = category_id;
    END
    $do$;
  $$,
  'non-seed rows still allow CRUD operations'
);

SELECT * FROM finish();

ROLLBACK;
