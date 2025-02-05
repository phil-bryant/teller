CREATE TABLE teller.account_details_links (
    account_id TEXT REFERENCES teller.account(account_id),
    details_id TEXT REFERENCES teller.account_details(details_id),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (account_id, details_id)
);
COMMENT ON TABLE teller.account_details_links IS 'Links table between accounts and their details';
