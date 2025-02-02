CREATE TABLE teller.transaction (
    id TEXT PRIMARY KEY,
    amount TEXT NOT NULL,
    date TEXT NOT NULL,
    description TEXT NOT NULL,
    status TEXT NOT NULL,
    type TEXT NOT NULL,
    account_id TEXT NOT NULL REFERENCES teller.account(id),
    running_balance TEXT,
    counterparty_id BIGINT REFERENCES teller.transaction_counterparty(id),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);
COMMENT ON TABLE teller.transaction IS 'Transaction information for an account';
COMMENT ON COLUMN teller.transaction.amount IS 'The signed amount of the transaction';
COMMENT ON COLUMN teller.transaction.date IS 'The date of the transaction';
COMMENT ON COLUMN teller.transaction.description IS 'The transaction description';
COMMENT ON COLUMN teller.transaction.status IS 'The transaction status';
COMMENT ON COLUMN teller.transaction.running_balance IS 'The running balance after this transaction'; 