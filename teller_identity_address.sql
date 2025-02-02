CREATE TABLE teller.identity_address (
    identity_id BIGINT NOT NULL REFERENCES teller.identity(id),
    address_id BIGINT NOT NULL REFERENCES teller.address(id),
    id BIGSERIAL PRIMARY KEY,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(identity_id, address_id)
);
COMMENT ON TABLE teller.identity_address IS 'Junction table linking identities to their addresses'; 