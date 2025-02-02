CREATE TABLE teller.transaction_type (
    id BIGSERIAL PRIMARY KEY,
    code TEXT NOT NULL UNIQUE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);
COMMENT ON TABLE teller.transaction_type IS 'Lookup table for transaction types';
COMMENT ON COLUMN teller.transaction_type.code IS 'The type code for the transaction, e.g. card_payment';