-- R055: Ensure ingest runtime role can reconcile/prune stale transactions.
GRANT DELETE ON TABLE teller.transaction TO teller_write;
GRANT DELETE ON TABLE teller.transaction_links TO teller_write;
GRANT DELETE ON TABLE teller.transaction_details TO teller_write;
GRANT DELETE ON TABLE teller.transaction_details_counterparty TO teller_write;

-- R055: Audit trigger writes must remain permitted during DELETE operations.
GRANT INSERT ON TABLE teller.audit_log TO teller_write;
