CREATE TABLE teller.counterparty (
    id BIGSERIAL PRIMARY KEY,
    name TEXT NOT NULL,
    type teller.counterparty_type NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);
COMMENT ON TABLE teller.counterparty IS 'Information about transaction counterparties';
COMMENT ON COLUMN teller.counterparty.name IS 'The name of the counterparty';
COMMENT ON COLUMN teller.counterparty.type IS 'The type of counterparty: organization or person'; 