CREATE TABLE teller.email (
    id BIGSERIAL PRIMARY KEY,
    data TEXT NOT NULL,
    identity_id BIGINT NOT NULL REFERENCES teller.identity(id),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);
COMMENT ON TABLE teller.email IS 'Email addresses associated with an identity';
COMMENT ON COLUMN teller.email.data IS 'The email address';
COMMENT ON COLUMN teller.email.identity_id IS 'Reference to the identity this email belongs to'; 