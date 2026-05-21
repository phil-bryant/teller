CREATE TABLE IF NOT EXISTS teller.transaction_details_counterparty (
    name TEXT NOT NULL,
    type teller.counterparty_type NOT NULL,
    transaction_details_counterparty_id BIGSERIAL PRIMARY KEY,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);
COMMENT ON TABLE teller.transaction_details_counterparty IS 'Table for teller_transaction_details_counterparty.py';
COMMENT ON COLUMN teller.transaction_details_counterparty.name IS 'The name of the counterparty';
COMMENT ON COLUMN teller.transaction_details_counterparty.type IS 'The type of counterparty';