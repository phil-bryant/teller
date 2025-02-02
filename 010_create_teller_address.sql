CREATE TABLE teller.address (
    id BIGSERIAL PRIMARY KEY,
    primary_address BOOLEAN NOT NULL DEFAULT false,
    data_id BIGINT NOT NULL REFERENCES teller.address_data(id),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);
COMMENT ON TABLE teller.address IS 'Address information associated with an identity';
COMMENT ON COLUMN teller.address.primary_address IS 'Whether this is the primary address for the identity';
COMMENT ON COLUMN teller.address.data_id IS 'Reference to the address data details'; 