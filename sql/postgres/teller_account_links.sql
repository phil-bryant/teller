CREATE TABLE IF NOT EXISTS teller.account_links (
    self_link TEXT NOT NULL,
    details TEXT,
    balances TEXT,
    transactions TEXT,
    account_links_id BIGSERIAL PRIMARY KEY,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);
COMMENT ON TABLE teller.account_links IS 'Table for teller_account_links.py';
COMMENT ON COLUMN teller.account_links.self_link IS 'A link to the account. e.g., https://api.teller.io/accounts/acc_oiin624kqjrg2mp2ea000';
COMMENT ON COLUMN teller.account_links.details IS 'Link to account details. e.g., https://api.teller.io/accounts/acc_oiin624kqjrg2mp2ea000/details';
COMMENT ON COLUMN teller.account_links.balances IS 'Link to account balances. e.g., https://api.teller.io/accounts/acc_oiin624kqjrg2mp2ea000/balances';
COMMENT ON COLUMN teller.account_links.transactions IS 'Link to account transactions. e.g., https://api.teller.io/accounts/acc_oiin624kqjrg2mp2ea000/transactions'; 