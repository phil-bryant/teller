CREATE TABLE IF NOT EXISTS teller.transaction (
    account_id TEXT NOT NULL REFERENCES teller.account(account_id),
    amount DECIMAL(15,2) NOT NULL,
    date DATE NOT NULL,
    description TEXT NOT NULL,
    transaction_details_id BIGINT NOT NULL UNIQUE REFERENCES teller.transaction_details(transaction_details_id),
    status teller.transaction_status NOT NULL,
    transaction_id TEXT PRIMARY KEY,
    transaction_links_id BIGINT NOT NULL UNIQUE REFERENCES teller.transaction_links(transaction_links_id),
    running_balance DECIMAL(15,2),
    transaction_type_id BIGINT NOT NULL REFERENCES teller.transaction_type(transaction_type_id),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);
COMMENT ON TABLE teller.transaction IS 'Table for teller_transactions.py';
COMMENT ON COLUMN teller.transaction.account_id IS 'The id of the account that the transaction belongs to';
COMMENT ON COLUMN teller.transaction.amount IS 'The signed amount of the transaction as a string';
COMMENT ON COLUMN teller.transaction.date IS 'The date of the transaction without timezone info because this varies by institution';
COMMENT ON COLUMN teller.transaction.description IS 'The unprocessed transaction description as it appears on the bank statement';
COMMENT ON COLUMN teller.transaction.transaction_details_id IS 'Reference to additional transaction enrichment information';
COMMENT ON COLUMN teller.transaction.status IS 'The transaction status: posted or pending';
COMMENT ON COLUMN teller.transaction.transaction_id IS 'The id of the transaction itself';
COMMENT ON COLUMN teller.transaction.running_balance IS 'The running balance of the account that the transaction belongs to. Only present on transactions with a posted status';
COMMENT ON COLUMN teller.transaction.transaction_type_id IS 'The type code of the transaction, e.g. card_payment'; 