CREATE TABLE teller.address (
    primary_address BOOLEAN NOT NULL DEFAULT false,
    data_id BIGINT NOT NULL REFERENCES teller.address_data(id),
    id BIGSERIAL PRIMARY KEY,
    identity_id BIGINT NOT NULL REFERENCES teller.identity(id),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);
COMMENT ON TABLE teller.address IS 'Table for teller_address.py';
COMMENT ON COLUMN teller.address.primary_address IS 'Whether this is the primary address for the identity';
COMMENT ON COLUMN teller.address.data_id IS 'Reference to the address_data table. This design allows multiple people to share an address independent of primary designation';
COMMENT ON COLUMN teller.address.identity_id IS 'Reference to the identity this address belongs to' 