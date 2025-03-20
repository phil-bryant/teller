CREATE TABLE teller.institution (
    institution_id TEXT PRIMARY KEY,
    name TEXT NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);
COMMENT ON TABLE teller.institution IS 'Table for teller_institution.py';
COMMENT ON COLUMN teller.institution.institution_id IS 'The unique identifier for the institution';
COMMENT ON COLUMN teller.institution.name IS 'The name of the financial institution'; 