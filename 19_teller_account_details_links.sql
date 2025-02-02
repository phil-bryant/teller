CREATE TABLE teller.account_details_links (
    account_id TEXT PRIMARY KEY REFERENCES teller.account(id),
    self_link TEXT NOT NULL,
    account_link TEXT NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);
COMMENT ON TABLE teller.account_details_links IS 'Links associated with account details';
COMMENT ON COLUMN teller.account_details_links.self_link IS 'A self link to the account details. e.g., https://api.teller.io/accounts/acc_oiin624kqjrg2mp2ea000/details';
COMMENT ON COLUMN teller.account_details_links.account_link IS 'A link to the account that owns the details. e.g., https://api.teller.io/accounts/acc_oiin624kqjrg2mp2ea000'; 