CREATE TABLE IF NOT EXISTS teller.transaction_links (
    self_link TEXT NOT NULL UNIQUE,
    account TEXT NOT NULL,
    transaction_links_id BIGSERIAL PRIMARY KEY,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);
COMMENT ON TABLE teller.transaction_links IS 'Links associated with a transaction';
COMMENT ON COLUMN teller.transaction_links.self_link IS 'A self link to the transaction. e.g., https://api.teller.io/accounts/acc_oiin624kqjrg2mp2ea000/transactions/txn_oiluj93igokseo0i3a000';
COMMENT ON COLUMN teller.transaction_links.account IS 'Link to the associated account. e.g., https://api.teller.io/accounts/acc_oiin624kqjrg2mp2ea000'; 