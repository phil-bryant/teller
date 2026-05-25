CREATE TABLE IF NOT EXISTS teller.account_balances_links (
    self_link TEXT NOT NULL UNIQUE,
    account_link TEXT NOT NULL UNIQUE,
    account_balances_links_id BIGSERIAL PRIMARY KEY,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);
COMMENT ON TABLE teller.account_balances_links IS 'Table for teller_account_balances_links.py';
COMMENT ON COLUMN teller.account_balances_links.self_link IS 'A self link to the account balances. e.g., https://api.teller.io/accounts/acc_oiin624kqjrg2mp2ea000/balances';
COMMENT ON COLUMN teller.account_balances_links.account_link IS 'A link to the account that owns the balances. e.g., https://api.teller.io/accounts/acc_oiin624kqjrg2mp2ea000';