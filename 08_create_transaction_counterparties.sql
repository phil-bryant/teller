CREATE TABLE teller.transaction_counterparties (
    id BIGSERIAL PRIMARY KEY,
    name TEXT,
    type teller.counterparty_type,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);
COMMENT ON TABLE teller.transaction_counterparties IS 'An object containing information regarding the transaction''s recipient';
COMMENT ON COLUMN teller.transaction_counterparties.name IS 'The processed counterparty name';
COMMENT ON COLUMN teller.transaction_counterparties.type IS 'The counterparty type: organization or person'; 