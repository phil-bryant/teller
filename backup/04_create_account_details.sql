CREATE TABLE teller.account_details (
    account_id VARCHAR(50) PRIMARY KEY REFERENCES teller.accounts(id),
    account_number VARCHAR(50) NOT NULL,
    routing_number_ach VARCHAR(50),
    routing_number_wire VARCHAR(50),
    routing_number_bacs VARCHAR(50),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);
COMMENT ON TABLE teller.account_details IS 'The account details object contains the financial account''s account number and routing information';
COMMENT ON COLUMN teller.account_details.account_number IS 'The account number';
COMMENT ON COLUMN teller.account_details.routing_number_ach IS 'The account''s routing number for ACH transactions';
COMMENT ON COLUMN teller.account_details.routing_number_wire IS 'The account''s wire routing number';
COMMENT ON COLUMN teller.account_details.routing_number_bacs IS 'The account''s BACS sort code'; 