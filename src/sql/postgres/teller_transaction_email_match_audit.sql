CREATE TABLE IF NOT EXISTS matchy.transaction_email_match_audit (
    match_audit_id BIGSERIAL PRIMARY KEY,
    match_id BIGINT NOT NULL REFERENCES matchy.transaction_email_match(match_id) ON DELETE CASCADE,
    from_state matchy.transaction_email_match_state,
    to_state matchy.transaction_email_match_state NOT NULL,
    actor matchy.transaction_email_match_selected_by NOT NULL,
    note TEXT,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_transaction_email_match_audit_match_id
    ON matchy.transaction_email_match_audit(match_id);

COMMENT ON TABLE matchy.transaction_email_match_audit IS 'Append-only log of transaction-email match state transitions';
