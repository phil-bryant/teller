CREATE TABLE teller.account_links (
    id BIGSERIAL PRIMARY KEY,
    self_link TEXT NOT NULL,
    details TEXT,
    balances TEXT,
    transactions TEXT,
    account_id TEXT NOT NULL REFERENCES teller.account(id),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);
COMMENT ON TABLE teller.account_links IS 'Links associated with an account';
COMMENT ON COLUMN teller.account_links.self_link IS 'A self link to the account';
COMMENT ON COLUMN teller.account_links.details IS 'Link to account details';
COMMENT ON COLUMN teller.account_links.balances IS 'Link to account balances';
COMMENT ON COLUMN teller.account_links.transactions IS 'Link to account transactions'; 