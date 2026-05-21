CREATE TABLE IF NOT EXISTS teller.account_balances (
    account_id TEXT NOT NULL REFERENCES teller.account(account_id),
    ledger NUMERIC(15,2),
    account_balances_links_id BIGINT NOT NULL REFERENCES teller.account_balances_links(account_balances_links_id),
    available NUMERIC(15,2),
    account_balances_id BIGSERIAL PRIMARY KEY,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);
COMMENT ON TABLE teller.account_balances IS 'Table for teller_account_balances.py';
COMMENT ON COLUMN teller.account_balances.ledger IS 'The account''s ledger balance in base currency units. The ledger balance is the total amount of funds in the account';
COMMENT ON COLUMN teller.account_balances.available IS 'The account''s available balance in base currency units. The available balance is the ledger balance net any pending inflows or outflows'; 