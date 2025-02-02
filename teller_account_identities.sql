CREATE TABLE teller.account_identities (
    account_id TEXT NOT NULL REFERENCES teller.account(id),
    identity_id BIGINT NOT NULL REFERENCES teller.identity(id),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(account_id, identity_id)
);
COMMENT ON TABLE teller.account_identities IS 'Table for teller_account_identities.py';
COMMENT ON COLUMN teller.account_identities.account_id IS 'Reference to the account';
COMMENT ON COLUMN teller.account_identities.identity_id IS 'Reference to the identity'; 