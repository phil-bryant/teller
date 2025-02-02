CREATE TABLE teller.balances (
    id BIGSERIAL PRIMARY KEY,
    account_id TEXT NOT NULL REFERENCES teller.account(id),
    ledger TEXT,
    available TEXT,
    links_id BIGINT REFERENCES teller.account_balances_links(id),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);
COMMENT ON TABLE teller.balances IS 'The account balances API provides your application with live, real-time account balances';
COMMENT ON COLUMN teller.balances.ledger IS 'The account''s ledger balance. The ledger balance is the total amount of funds in the account';
COMMENT ON COLUMN teller.balances.available IS 'The account''s available balance. The available balance is the ledger balance net any pending inflows or outflows'; 