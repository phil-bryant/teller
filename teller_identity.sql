CREATE TABLE teller.identity (
    id BIGSERIAL PRIMARY KEY,
    type teller.identity_type NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);
COMMENT ON TABLE teller.identity IS 'Table for teller_identity.py';
COMMENT ON COLUMN teller.identity.type IS 'The type of identity: organization or person'; 