CREATE TABLE IF NOT EXISTS teller.account_details_links (
    self_link TEXT NOT NULL UNIQUE,
    account TEXT NOT NULL UNIQUE,
    account_details_links_id BIGSERIAL PRIMARY KEY,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);
COMMENT ON TABLE teller.account_details_links IS 'Table for teller_account_details_links.py';
COMMENT ON COLUMN teller.account_details_links.self_link IS 'A link to the account details. e.g., https://api.teller.io/accounts/acc_oiin624kqjrg2mp2ea000/details';
COMMENT ON COLUMN teller.account_details_links.account IS 'A link to the account that owns the details. e.g., https://api.teller.io/accounts/acc_oiin624kqjrg2mp2ea000';