CREATE TABLE teller.institutions (
    id VARCHAR(50) PRIMARY KEY,
    name VARCHAR(100) NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);
COMMENT ON TABLE teller.institutions IS 'A financial institution that holds accounts. An institution represents a bank or credit union where a user has one or more accounts.';
COMMENT ON COLUMN teller.institutions.id IS 'The unique identifier for the institution';
COMMENT ON COLUMN teller.institutions.name IS 'The name of the financial institution'; 