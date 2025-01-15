CREATE TABLE teller.account_links (
    account_id VARCHAR(50) PRIMARY KEY REFERENCES teller.accounts(id),
    self_link TEXT NOT NULL,
    balances_link TEXT,
    transactions_link TEXT,
    details_link TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);
COMMENT ON TABLE teller.account_links IS 'An object containing links to related resources. A link indicates the enrollment supports that type of resource. Not every institution implements all of the capabilities that Teller supports';
COMMENT ON COLUMN teller.account_links.self_link IS 'A self link to the account. e.g., https://api.teller.io/accounts/acc_oiin624kqjrg2mp2ea000';
COMMENT ON COLUMN teller.account_links.balances_link IS 'A link to the account''s live balances. e.g., https://api.teller.io/accounts/acc_oiin624kqjrg2mp2ea000/balances';
COMMENT ON COLUMN teller.account_links.transactions_link IS 'A link to the account''s transactions. e.g., https://api.teller.io/accounts/acc_oiin624kqjrg2mp2ea000/transactions';
COMMENT ON COLUMN teller.account_links.details_link IS 'A link to the account''s details, such as account number and routing numbers. e.g., https://api.teller.io/accounts/acc_oiin624kqjrg2mp2ea000/details';

CREATE TABLE teller.account_detail_links (
    account_id VARCHAR(50) PRIMARY KEY REFERENCES teller.accounts(id),
    self_link TEXT NOT NULL,
    account_link TEXT NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);
COMMENT ON TABLE teller.account_detail_links IS 'Links associated with account details';
COMMENT ON COLUMN teller.account_detail_links.self_link IS 'A self link to the account details. e.g., https://api.teller.io/accounts/acc_oiin624kqjrg2mp2ea000/details';
COMMENT ON COLUMN teller.account_detail_links.account_link IS 'A link to the account that owns the details. e.g., https://api.teller.io/accounts/acc_oiin624kqjrg2mp2ea000';

CREATE TABLE teller.account_balance_links (
    account_id VARCHAR(50) PRIMARY KEY REFERENCES teller.accounts(id),
    self_link TEXT NOT NULL,
    account_link TEXT NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);
COMMENT ON TABLE teller.account_balance_links IS 'Links associated with account balances';
COMMENT ON COLUMN teller.account_balance_links.self_link IS 'A self link to the account balances. e.g., https://api.teller.io/accounts/acc_oiin624kqjrg2mp2ea000/balances';
COMMENT ON COLUMN teller.account_balance_links.account_link IS 'A link to the account that owns the balances. e.g., https://api.teller.io/accounts/acc_oiin624kqjrg2mp2ea000';

    transaction_id VARCHAR(50) PRIMARY KEY REFERENCES teller.transactions(id),
    self_link TEXT NOT NULL,
    account_link TEXT NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);
