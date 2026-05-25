CREATE TABLE IF NOT EXISTS teller.account_details (
    account_id TEXT REFERENCES teller.account(account_id),
    account_number TEXT PRIMARY KEY,
    account_details_links_id BIGINT NOT NULL REFERENCES teller.account_details_links(account_details_links_id) UNIQUE,
    routing_numbers_id BIGINT REFERENCES teller.routing_numbers(routing_numbers_id) UNIQUE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);
COMMENT ON TABLE teller.account_details IS 'table for teller_account_details.py';
COMMENT ON COLUMN teller.account_details.account_number IS 'The account number'; 