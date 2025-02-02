CREATE TABLE teller.routing_numbers (
    id BIGSERIAL PRIMARY KEY,
    ach TEXT,
    wire TEXT,
    bacs TEXT,
    account_id TEXT NOT NULL REFERENCES teller.accounts(id),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);
COMMENT ON TABLE teller.routing_numbers IS 'Routing numbers associated with an account';
COMMENT ON COLUMN teller.routing_numbers.ach IS 'The account''s routing number for ACH transactions';
COMMENT ON COLUMN teller.routing_numbers.wire IS 'The account''s wire routing number';
COMMENT ON COLUMN teller.routing_numbers.bacs IS 'The account''s BACS sort code'; 