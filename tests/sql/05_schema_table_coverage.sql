-- pgTAP: broad table coverage across Teller schema objects.
BEGIN;

SELECT plan(27);

SELECT has_table('teller', 'audit_log', 'teller.audit_log table exists');
SELECT has_table('teller', 'institution', 'teller.institution table exists');
SELECT has_table('teller', 'account_links', 'teller.account_links table exists');
SELECT has_table('teller', 'account', 'teller.account table exists');
SELECT has_table('teller', 'account_details_links', 'teller.account_details_links table exists');
SELECT has_table('teller', 'account_details', 'teller.account_details table exists');
SELECT has_table('teller', 'account_balances_links', 'teller.account_balances_links table exists');
SELECT has_table('teller', 'account_balances', 'teller.account_balances table exists');
SELECT has_table('teller', 'account_identities', 'teller.account_identities table exists');
SELECT has_table('teller', 'identity', 'teller.identity table exists');
SELECT has_table('teller', 'identity_name', 'teller.identity_name table exists');
SELECT has_table('teller', 'identity_address', 'teller.identity_address table exists');
SELECT has_table('teller', 'identity_address_data', 'teller.identity_address_data table exists');
SELECT has_table('teller', 'identity_email', 'teller.identity_email table exists');
SELECT has_table('teller', 'identity_phone_number', 'teller.identity_phone_number table exists');
SELECT has_table('teller', 'routing_numbers', 'teller.routing_numbers table exists');
SELECT has_table('teller', 'transaction', 'teller.transaction table exists');
SELECT has_table('teller', 'transaction_links', 'teller.transaction_links table exists');
SELECT has_table('teller', 'transaction_details_counterparty', 'teller.transaction_details_counterparty table exists');
SELECT has_table('teller', 'transaction_details', 'teller.transaction_details table exists');
SELECT has_table('teller', 'transaction_type', 'teller.transaction_type table exists');
SELECT has_table('matchy', 'transaction_email_candidate', 'matchy.transaction_email_candidate table exists');
SELECT has_table('matchy', 'transaction_email_match_run', 'matchy.transaction_email_match_run table exists');
SELECT has_table('matchy', 'transaction_email_match', 'matchy.transaction_email_match table exists');
SELECT has_table('matchy', 'transaction_email_match_audit', 'matchy.transaction_email_match_audit table exists');
SELECT has_table('classy', 'transaction_nys_snw_category', 'classy.transaction_nys_snw_category table exists');
SELECT has_table('classy', 'nys_snw_category', 'classy.nys_snw_category table exists');

SELECT * FROM finish();

ROLLBACK;
