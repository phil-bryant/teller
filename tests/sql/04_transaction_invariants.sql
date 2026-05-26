-- pgTAP: transaction/reporting invariants for FK, trigger, and view behavior.
BEGIN;

SELECT plan(7);

SELECT has_view('teller', 'transaction_info_view', 'transaction_info_view remains available');

SELECT ok(
  EXISTS (
    SELECT 1
      FROM pg_constraint c
      JOIN pg_class rel ON rel.oid = c.conrelid
      JOIN pg_namespace ns ON ns.oid = rel.relnamespace
     WHERE ns.nspname = 'teller'
       AND rel.relname = 'transaction'
       AND c.contype = 'f'
       AND pg_get_constraintdef(c.oid) ILIKE '%account_id%'
  ),
  'transaction.account_id foreign key is present'
);

SELECT ok(
  EXISTS (
    SELECT 1
      FROM pg_constraint c
      JOIN pg_class rel ON rel.oid = c.conrelid
      JOIN pg_namespace ns ON ns.oid = rel.relnamespace
     WHERE ns.nspname = 'teller'
       AND rel.relname = 'transaction_nys_snw_category'
       AND c.contype = 'f'
       AND c.confdeltype = 'c'
       AND pg_get_constraintdef(c.oid) ILIKE '%transaction_id%'
  ),
  'classification rows cascade on transaction delete'
);

SELECT has_trigger('teller', 'transaction', 'update_transaction_updated_at', 'transaction updated_at trigger exists');
SELECT has_trigger('teller', 'transaction_nys_snw_category', 'update_transaction_nys_snw_category_updated_at', 'classification updated_at trigger exists');

SELECT lives_ok(
  $$
    DO $do$
    DECLARE
      suffix text := replace(substr(md5(clock_timestamp()::text), 1, 12), '-', '');
      inst_id text := 'inst_pgtap_' || suffix;
      account_links_id_v bigint;
      account_id_v text := 'acc_pgtap_' || suffix;
      tx_type_id_v bigint;
      cp_id_v bigint;
      tx_details_id_v bigint;
      tx_links_id_v bigint;
      tx_id_v text := 'txn_pgtap_' || suffix;
    BEGIN
      INSERT INTO teller.institution (institution_id, name)
      VALUES (inst_id, 'pgTAP Institution');

      INSERT INTO teller.account_links (self_link, details, balances, transactions)
      VALUES (
        'https://example.local/accounts/' || account_id_v,
        'https://example.local/accounts/' || account_id_v || '/details',
        'https://example.local/accounts/' || account_id_v || '/balances',
        'https://example.local/accounts/' || account_id_v || '/transactions'
      )
      RETURNING account_links_id INTO account_links_id_v;

      INSERT INTO teller.account (
        currency, enrollment_id, account_id, institution_id, last_four, account_links_id, name, type, subtype, status
      )
      VALUES ('USD', 'enr_' || suffix, account_id_v, inst_id, '1234', account_links_id_v, 'pgTAP Account ' || suffix,
              'depository', 'checking', 'open');

      INSERT INTO teller.transaction_type (code) VALUES ('pgtap_type_' || suffix)
      RETURNING transaction_type_id INTO tx_type_id_v;

      INSERT INTO teller.transaction_details_counterparty (name, type)
      VALUES ('pgTAP Merchant ' || suffix, 'organization')
      RETURNING transaction_details_counterparty_id INTO cp_id_v;

      INSERT INTO teller.transaction_details (processing_status, category, transaction_details_counterparty_id)
      VALUES ('complete', 'general', cp_id_v)
      RETURNING transaction_details_id INTO tx_details_id_v;

      INSERT INTO teller.transaction_links (self_link, account)
      VALUES ('https://example.local/transactions/' || tx_id_v, 'https://example.local/accounts/' || account_id_v)
      RETURNING transaction_links_id INTO tx_links_id_v;

      INSERT INTO teller.transaction (
        account_id, amount, date, description, transaction_details_id, status, transaction_id, transaction_links_id, running_balance, transaction_type_id
      ) VALUES (
        account_id_v, -12.34, DATE '2026-05-20', 'pgTAP coffee', tx_details_id_v, 'posted', tx_id_v, tx_links_id_v, 100.00, tx_type_id_v
      );

      IF NOT EXISTS (
        SELECT 1
          FROM teller.transaction_info_view
         WHERE description = 'pgTAP coffee'
           AND code = 'pgtap_type_' || suffix
           AND counterparty_name = 'pgTAP Merchant ' || suffix
      ) THEN
        RAISE EXCEPTION 'transaction_info_view did not expose inserted transaction row';
      END IF;
    END
    $do$;
  $$,
  'transaction_info_view surfaces joined transaction details and type'
);

SELECT lives_ok(
  $$
    DO $do$
    DECLARE
      suffix text := replace(substr(md5(clock_timestamp()::text), 1, 12), '-', '');
      inst_id text := 'inst_pgtap_cascade_' || suffix;
      account_links_id_v bigint;
      account_id_v text := 'acc_pgtap_cascade_' || suffix;
      tx_type_id_v bigint;
      tx_details_id_v bigint;
      tx_links_id_v bigint;
      tx_id_v text := 'txn_pgtap_cascade_' || suffix;
      category_id_v bigint;
    BEGIN
      INSERT INTO teller.institution (institution_id, name)
      VALUES (inst_id, 'pgTAP Cascade Institution');

      INSERT INTO teller.account_links (self_link, details, balances, transactions)
      VALUES (
        'https://example.local/accounts/' || account_id_v,
        'https://example.local/accounts/' || account_id_v || '/details',
        'https://example.local/accounts/' || account_id_v || '/balances',
        'https://example.local/accounts/' || account_id_v || '/transactions'
      )
      RETURNING account_links_id INTO account_links_id_v;

      INSERT INTO teller.account (
        currency, enrollment_id, account_id, institution_id, last_four, account_links_id, name, type, subtype, status
      )
      VALUES ('USD', 'enr_' || suffix, account_id_v, inst_id, '5678', account_links_id_v, 'pgTAP Cascade Account ' || suffix,
              'depository', 'checking', 'open');

      INSERT INTO teller.transaction_type (code) VALUES ('pgtap_cascade_type_' || suffix)
      RETURNING transaction_type_id INTO tx_type_id_v;

      INSERT INTO teller.transaction_details (processing_status, category, transaction_details_counterparty_id)
      VALUES ('complete', 'general', NULL)
      RETURNING transaction_details_id INTO tx_details_id_v;

      INSERT INTO teller.transaction_links (self_link, account)
      VALUES ('https://example.local/transactions/' || tx_id_v, 'https://example.local/accounts/' || account_id_v)
      RETURNING transaction_links_id INTO tx_links_id_v;

      INSERT INTO teller.transaction (
        account_id, amount, date, description, transaction_details_id, status, transaction_id, transaction_links_id, running_balance, transaction_type_id
      ) VALUES (
        account_id_v, -8.55, DATE '2026-05-21', 'pgTAP cascade test', tx_details_id_v, 'posted', tx_id_v, tx_links_id_v, 90.00, tx_type_id_v
      );

      INSERT INTO teller.nys_snw_category (level_1_name, categorization, applicability)
      VALUES ('PGTAP', 'Cascade', 'All')
      RETURNING nys_snw_category_id INTO category_id_v;

      INSERT INTO teller.transaction_nys_snw_category (transaction_id, nys_snw_category_id, type)
      VALUES (tx_id_v, category_id_v, 'user');

      UPDATE teller.transaction_nys_snw_category
         SET type = 'ai'
       WHERE transaction_id = tx_id_v;

      IF NOT EXISTS (
        SELECT 1
          FROM teller.transaction_nys_snw_category
         WHERE transaction_id = tx_id_v
           AND type = 'ai'
      ) THEN
        RAISE EXCEPTION 'classification type did not update as expected';
      END IF;

      DELETE FROM teller.transaction WHERE transaction_id = tx_id_v;

      IF EXISTS (
        SELECT 1
          FROM teller.transaction_nys_snw_category
         WHERE transaction_id = tx_id_v
      ) THEN
        RAISE EXCEPTION 'classification row did not cascade-delete with transaction';
      END IF;
    END
    $do$;
  $$,
  'classification rows update timestamps and cascade-delete with parent transaction'
);

SELECT * FROM finish();

ROLLBACK;
