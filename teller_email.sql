CREATE TABLE teller.email (
    data TEXT NOT NULL UNIQUE,
    id BIGSERIAL PRIMARY KEY,
    identity_id BIGINT NOT NULL REFERENCES teller.identity(id),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);
COMMENT ON TABLE teller.email IS 'Table for teller_email.py';
COMMENT ON COLUMN teller.email.data IS 'The email address';
COMMENT ON COLUMN teller.email.identity_id IS 'Reference to the identity this email belongs to'; 