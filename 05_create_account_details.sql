CREATE TABLE teller.account_details (
    account_id TEXT PRIMARY KEY REFERENCES teller.accounts(id),
    account_number TEXT NOT NULL,
    routing_number_ach TEXT,
    routing_number_wire TEXT,
    routing_number_bacs TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);
COMMENT ON TABLE teller.account_details IS 'The account details object contains the financial account''s account number and routing information';
COMMENT ON COLUMN teller.account_details.account_number IS 'The account number';
COMMENT ON COLUMN teller.account_details.routing_number_ach IS 'The account''s routing number for ACH transactions';
COMMENT ON COLUMN teller.account_details.routing_number_wire IS 'The account''s wire routing number';
COMMENT ON COLUMN teller.account_details.routing_number_bacs IS 'The account''s BACS sort code'; 