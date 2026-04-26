-- pgTAP: transaction_info_view exposes stable reporting columns.
BEGIN;

SELECT plan(8);

SELECT col_is_present('teller', 'transaction_info_view', 'institution_id', 'institution_id column exists');
SELECT col_is_present('teller', 'transaction_info_view', 'amount', 'amount column exists');
SELECT col_is_present('teller', 'transaction_info_view', 'date', 'date column exists');
SELECT col_is_present('teller', 'transaction_info_view', 'description', 'description column exists');
SELECT col_is_present('teller', 'transaction_info_view', 'code', 'code column exists');
SELECT col_is_present('teller', 'transaction_info_view', 'category', 'category column exists');
SELECT col_is_present('teller', 'transaction_info_view', 'counterparty_name', 'counterparty_name column exists');
SELECT col_is_present('teller', 'transaction_info_view', 'counterparty_type', 'counterparty_type column exists');

SELECT * FROM finish();

ROLLBACK;
