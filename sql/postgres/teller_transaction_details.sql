CREATE TABLE IF NOT EXISTS teller.transaction_details (
    processing_status TEXT NOT NULL,
    category teller.transaction_category,
    transaction_details_counterparty_id BIGINT REFERENCES teller.transaction_details_counterparty(transaction_details_counterparty_id),
    transaction_details_id BIGSERIAL PRIMARY KEY,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);
COMMENT ON TABLE teller.transaction_details IS 'Table for teller_transaction_details.py';
COMMENT ON COLUMN teller.transaction_details.processing_status IS 'Indicates the transaction enrichment processing status';
COMMENT ON COLUMN teller.transaction_details.category IS 'The category that the transaction belongs to';