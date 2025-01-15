CREATE TABLE teller.account_balances (
    account_id VARCHAR(50) PRIMARY KEY REFERENCES teller.accounts(id),
    ledger DECIMAL(19,2),
    available DECIMAL(19,2),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);
COMMENT ON TABLE teller.account_balances IS 'The account balances API provides your application with live, real-time account balances. At least one balance (ledger or available) is always provided';
COMMENT ON COLUMN teller.account_balances.ledger IS 'The account''s ledger balance. The ledger balance is the total amount of funds in the account';
COMMENT ON COLUMN teller.account_balances.available IS 'The account''s available balance. The available balance is the ledger balance net any pending inflows or outflows'; 