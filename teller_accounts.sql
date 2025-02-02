CREATE TABLE teller.account (
    currency TEXT NOT NULL,
    enrollment_id TEXT NOT NULL,
    id TEXT PRIMARY KEY,
    institution_id TEXT NOT NULL REFERENCES teller.institutions(id),
    last_four TEXT NOT NULL,
    account_links_id BIGINT NOT NULL REFERENCES teller.account_links(id),
    name TEXT NOT NULL,
    type teller.account_type NOT NULL,
    subtype teller.account_subtype NOT NULL,
    status teller.account_status NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);
COMMENT ON TABLE teller.account IS 'Table for teller_accounts.py';
COMMENT ON COLUMN teller.account.currency IS 'The ISO 4217 currency code of the account';
COMMENT ON COLUMN teller.account.enrollment_id IS 'The id of the enrollment that the account belongs to';
COMMENT ON COLUMN teller.account.last_four IS 'The last four digits of the account number';
COMMENT ON COLUMN teller.account.account_links_id IS 'Reference to the account_links table';
COMMENT ON COLUMN teller.account.name IS 'The account''s name';
COMMENT ON COLUMN teller.account.type IS 'The type of account. Either depository or credit';
COMMENT ON COLUMN teller.account.subtype IS 'The account''s subtype';
COMMENT ON COLUMN teller.account.status IS 'The account''s status: open or closed'; 