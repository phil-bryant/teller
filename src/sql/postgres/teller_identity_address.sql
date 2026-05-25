CREATE TABLE IF NOT EXISTS teller.identity_address (
    primary_address BOOLEAN NOT NULL DEFAULT false,
    identity_address_data_id BIGINT NOT NULL REFERENCES teller.identity_address_data(identity_address_data_id),
    identity_address_id BIGSERIAL PRIMARY KEY,
    identity_id BIGINT NOT NULL REFERENCES teller.identity(identity_id),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(identity_address_data_id, identity_id)
);
COMMENT ON TABLE teller.identity_address IS 'Table for teller_identity_address.py';
COMMENT ON COLUMN teller.identity_address.primary_address IS 'Whether this is the primary address for the identity';
COMMENT ON COLUMN teller.identity_address.identity_address_data_id IS 'Reference to the identity_address_data table. This design allows multiple people to share an address independent of primary designation';
COMMENT ON COLUMN teller.identity_address.identity_id IS 'Reference to the identity this address belongs to' 