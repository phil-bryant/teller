CREATE TABLE teller.transaction_details_counterparty (
    name TEXT NOT NULL,
    type teller.counterparty_type NOT NULL,
    id BIGSERIAL PRIMARY KEY,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);
COMMENT ON TABLE teller.transaction_details_counterparty IS 'Information about the counterparty in a transaction_details';
COMMENT ON COLUMN teller.transaction_details_counterparty.name IS 'The name of the counterparty';
COMMENT ON COLUMN teller.transaction_details_counterparty.type IS 'The type of counterparty';