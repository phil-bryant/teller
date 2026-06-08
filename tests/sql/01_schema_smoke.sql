-- pgTAP: core teller schema objects exist.
BEGIN;

SELECT plan(6);

SELECT has_schema('teller', 'Schema teller exists');
SELECT has_schema('classy', 'Schema classy exists');
SELECT has_schema('matchy', 'Schema matchy exists');
SELECT has_table('teller', 'transaction', 'Table teller.transaction exists');
SELECT has_view('teller', 'transaction_info_view', 'View teller.transaction_info_view exists');
SELECT has_function(
  'teller',
  'update_updated_at',
  ARRAY[]::text[],
  'Function teller.update_updated_at() exists'
);

SELECT * FROM finish();

ROLLBACK;
