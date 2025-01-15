CREATE TABLE teller.transactions (
    id VARCHAR(50) PRIMARY KEY,
    account_id VARCHAR(50) NOT NULL REFERENCES teller.accounts(id),
    amount DECIMAL(19,2) NOT NULL,
    date DATE NOT NULL,
    description TEXT NOT NULL,
    status teller.transaction_status NOT NULL,
    processing_status teller.processing_status NOT NULL,
    category teller.transaction_category,
    counterparty_id BIGINT REFERENCES teller.transaction_counterparties(id),
    running_balance DECIMAL(19,2),
    type VARCHAR(50) NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);
COMMENT ON TABLE teller.transactions IS 'The transactions API exposes the ledger transactions of a financial account';
COMMENT ON COLUMN teller.transactions.amount IS 'The signed amount of the transaction as a string';
COMMENT ON COLUMN teller.transactions.date IS 'The ISO 8601 date of the transaction';
COMMENT ON COLUMN teller.transactions.description IS 'The unprocessed transaction description as it appears on the bank statement';
COMMENT ON COLUMN teller.transactions.status IS 'The transaction''s status: posted or pending';
COMMENT ON COLUMN teller.transactions.processing_status IS 'Indicates the transaction enrichment processing status. Either pending or complete';
COMMENT ON COLUMN teller.transactions.category IS 'The category that the transaction belongs to';
COMMENT ON COLUMN teller.transactions.running_balance IS 'The running balance of the account that the transaction belongs to. Running balance is only present on transactions with a posted status';
COMMENT ON COLUMN teller.transactions.type IS 'The type code transaction, e.g. card_payment'; 