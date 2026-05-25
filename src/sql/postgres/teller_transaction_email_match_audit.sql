CREATE TABLE IF NOT EXISTS teller.transaction_email_match_audit (
    match_audit_id BIGSERIAL PRIMARY KEY,
    match_id BIGINT NOT NULL REFERENCES teller.transaction_email_match(match_id) ON DELETE CASCADE,
    from_state teller.transaction_email_match_state,
    to_state teller.transaction_email_match_state NOT NULL,
    actor teller.transaction_email_match_selected_by NOT NULL,
    note TEXT,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_transaction_email_match_audit_match_id
    ON teller.transaction_email_match_audit(match_id);

COMMENT ON TABLE teller.transaction_email_match_audit IS 'Append-only log of transaction-email match state transitions';
