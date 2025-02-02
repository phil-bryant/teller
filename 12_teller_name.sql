CREATE TABLE teller.name (
    id BIGSERIAL PRIMARY KEY,
    type teller.name_type NOT NULL,
    data TEXT NOT NULL,
    identity_id BIGINT NOT NULL REFERENCES teller.identity(id),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);
COMMENT ON TABLE teller.name IS 'Names associated with an identity';
COMMENT ON COLUMN teller.name.type IS 'The type of name: name or alias';
COMMENT ON COLUMN teller.name.data IS 'The name string';
COMMENT ON COLUMN teller.name.identity_id IS 'Reference to the identity this name belongs to'; 