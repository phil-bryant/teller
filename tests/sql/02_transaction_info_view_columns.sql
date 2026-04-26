-- pgTAP: transaction_info_view exposes stable reporting columns.
BEGIN;

SELECT plan(8);

SELECT has_column('teller', 'transaction_info_view', 'institution_id', 'institution_id column exists');
SELECT has_column('teller', 'transaction_info_view', 'amount', 'amount column exists');
SELECT has_column('teller', 'transaction_info_view', 'date', 'date column exists');
SELECT has_column('teller', 'transaction_info_view', 'description', 'description column exists');
SELECT has_column('teller', 'transaction_info_view', 'code', 'code column exists');
SELECT has_column('teller', 'transaction_info_view', 'category', 'category column exists');
SELECT has_column('teller', 'transaction_info_view', 'counterparty_name', 'counterparty_name column exists');
SELECT has_column('teller', 'transaction_info_view', 'counterparty_type', 'counterparty_type column exists');

SELECT * FROM finish();

ROLLBACK;
