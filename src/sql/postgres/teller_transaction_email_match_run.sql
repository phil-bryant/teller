CREATE TABLE IF NOT EXISTS teller.transaction_email_match_run (
    match_run_id BIGSERIAL PRIMARY KEY,
    transaction_id TEXT NOT NULL REFERENCES teller.transaction(transaction_id) ON DELETE CASCADE,
    trigger_source teller.matchy_trigger_source NOT NULL,
    model_name TEXT NOT NULL,
    prompt_version TEXT NOT NULL,
    status teller.matchy_run_status NOT NULL,
    started_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP,
    completed_at TIMESTAMP WITH TIME ZONE,
    error_text TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);
COMMENT ON TABLE teller.transaction_email_match_run IS 'Execution log rows for each matchy matching attempt per transaction';
COMMENT ON COLUMN teller.transaction_email_match_run.transaction_id IS 'Reference to teller transaction under evaluation';
