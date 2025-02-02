CREATE TABLE teller.transaction_details (
    processing_status TEXT NOT NULL,
    category teller.transaction_category,
    counterparty_id BIGINT REFERENCES teller.counterparty(id),
    id BIGSERIAL PRIMARY KEY,
    transactions_id TEXT NOT NULL UNIQUE REFERENCES teller.transactions(id),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);
COMMENT ON TABLE teller.transaction_details IS 'Detailed information about a transaction';
COMMENT ON COLUMN teller.transaction_details.category IS 'The category that the transaction belongs to';
COMMENT ON COLUMN teller.transaction_details.processing_status IS 'Indicates the transaction enrichment processing status';
COMMENT ON COLUMN teller.transaction_details.merchant_name IS 'The name of the merchant';
COMMENT ON COLUMN teller.transaction_details.merchant_website IS 'The website of the merchant if available';
COMMENT ON COLUMN teller.transaction_details.check_number IS 'The check number if applicable';
COMMENT ON COLUMN teller.transaction_details.type IS 'The type of transaction'; 