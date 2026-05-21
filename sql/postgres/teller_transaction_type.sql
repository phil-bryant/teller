CREATE TABLE IF NOT EXISTS teller.transaction_type (
    code TEXT NOT NULL UNIQUE,
    transaction_type_id BIGSERIAL PRIMARY KEY,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);
COMMENT ON TABLE teller.transaction_type IS 'Table for teller_transaction_type.py';
COMMENT ON COLUMN teller.transaction_type.code IS 'The type code for the transaction. e.g. card_payment';
