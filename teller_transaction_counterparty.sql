CREATE TABLE teller.transaction_counterparty (
    id BIGSERIAL PRIMARY KEY,
    name TEXT NOT NULL,
    type teller.counterparty_type NOT NULL,
    routing_number TEXT,
    account_number TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);
COMMENT ON TABLE teller.transaction_counterparty IS 'Information about the counterparty in a transaction';
COMMENT ON COLUMN teller.transaction_counterparty.name IS 'The name of the counterparty';
COMMENT ON COLUMN teller.transaction_counterparty.type IS 'The type of counterparty';
COMMENT ON COLUMN teller.transaction_counterparty.routing_number IS 'The routing number if available';
COMMENT ON COLUMN teller.transaction_counterparty.account_number IS 'The account number if available'; 