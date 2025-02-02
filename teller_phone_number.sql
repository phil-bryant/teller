CREATE TABLE teller.phone_number (
    type teller.phone_type NOT NULL,
    data TEXT NOT NULL,
    id BIGSERIAL PRIMARY KEY,
    identity_id BIGINT NOT NULL REFERENCES teller.identity(id),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);
COMMENT ON TABLE teller.phone_number IS 'Table for teller_phone_number.py';
COMMENT ON COLUMN teller.phone_number.type IS 'The type of phone number: home, work, or mobile';
COMMENT ON COLUMN teller.phone_number.data IS 'The phone number';
COMMENT ON COLUMN teller.phone_number.identity_id IS 'Reference to the identity this phone number belongs to'; 