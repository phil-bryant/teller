CREATE TABLE IF NOT EXISTS teller.identity_name (
    type teller.identity_name_type NOT NULL,
    data TEXT NOT NULL,
    identity_name_id BIGSERIAL PRIMARY KEY,
    identity_id BIGINT NOT NULL REFERENCES teller.identity(identity_id),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    UNIQUE (data, identity_id)
);
COMMENT ON TABLE teller.identity_name IS 'Table for teller_identity_name.py';
COMMENT ON COLUMN teller.identity_name.type IS 'The type of name: name or alias';
COMMENT ON COLUMN teller.identity_name.data IS 'The name string';
COMMENT ON COLUMN teller.identity_name.identity_id IS 'Reference to the identity this name belongs to';