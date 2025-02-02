CREATE TABLE teller.error (
    id BIGSERIAL PRIMARY KEY,
    code TEXT NOT NULL,
    message TEXT NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);
COMMENT ON TABLE teller.error IS 'Error information from the Teller API';
COMMENT ON COLUMN teller.error.code IS 'The error code returned by the API';
COMMENT ON COLUMN teller.error.message IS 'The error message describing what went wrong'; 