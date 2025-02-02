CREATE TABLE teller.account_details (
    account_id TEXT PRIMARY KEY REFERENCES teller.account(id),
    account_number TEXT NOT NULL,
    routing_numbers_id BIGINT REFERENCES teller.routing_numbers(id),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);
COMMENT ON TABLE teller.account_details IS 'Details about a specific account including account numbers and routing information';
COMMENT ON COLUMN teller.account_details.account_number IS 'The account number'; 