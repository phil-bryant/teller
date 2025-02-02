CREATE TABLE teller.account_identities (
    id BIGSERIAL PRIMARY KEY,
    account_id TEXT NOT NULL REFERENCES teller.accounts(id),
    owner_id BIGINT NOT NULL REFERENCES teller.identities(id),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);
COMMENT ON TABLE teller.account_identities IS 'Links accounts to their associated identity owners';
COMMENT ON COLUMN teller.account_identities.account_id IS 'Reference to the account';
COMMENT ON COLUMN teller.account_identities.owner_id IS 'Reference to the identity owner'; 