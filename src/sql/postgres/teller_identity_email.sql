CREATE TABLE IF NOT EXISTS teller.identity_email (
    data TEXT NOT NULL UNIQUE,
    identity_email_id BIGSERIAL PRIMARY KEY,
    identity_id BIGINT NOT NULL REFERENCES teller.identity(identity_id),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);
COMMENT ON TABLE teller.identity_email IS 'Table for teller_identity_email.py';
COMMENT ON COLUMN teller.identity_email.data IS 'The email address';
COMMENT ON COLUMN teller.identity_email.identity_id IS 'Reference to the identity this email belongs to';