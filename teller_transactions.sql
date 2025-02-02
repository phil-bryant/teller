CREATE TABLE teller.transactions (
    account_id TEXT NOT NULL REFERENCES teller.account(id),
    amount TEXT NOT NULL,
    date TEXT NOT NULL,
    description TEXT NOT NULL,
    transaction_details_id BIGINT NOT NULL UNIQUE REFERENCES teller.transaction_details(id),
    status teller.transaction_status NOT NULL,
    id TEXT PRIMARY KEY,
    running_balance TEXT,
    transaction_type_id BIGINT NOT NULL REFERENCES teller.transaction_type(id),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);
COMMENT ON TABLE teller.transactions IS 'Transaction information for an account';
COMMENT ON COLUMN teller.transaction.account_id IS 'The id of the account this transaction belongs to';
COMMENT ON COLUMN teller.transaction.amount IS 'The signed amount of the transaction';
COMMENT ON COLUMN teller.transaction.date IS 'The date of the transaction';
COMMENT ON COLUMN teller.transaction.description IS 'The transaction description';
COMMENT ON COLUMN teller.transaction.details_id IS 'Reference to transaction_details table';
COMMENT ON COLUMN teller.transaction.status IS 'The transaction status: posted or pending';
COMMENT ON COLUMN teller.transaction.id IS 'The unique identifier for the transaction';
COMMENT ON COLUMN teller.transaction.running_balance IS 'The running balance after this transaction';
COMMENT ON COLUMN teller.transaction.transaction_type_id IS 'Reference to the transaction type'; 