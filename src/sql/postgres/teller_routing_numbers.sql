CREATE TABLE IF NOT EXISTS teller.routing_numbers (
    ach TEXT UNIQUE,
    wire TEXT UNIQUE,
    bacs TEXT,
    routing_numbers_id BIGSERIAL PRIMARY KEY,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);
COMMENT ON TABLE teller.routing_numbers IS 'Table for teller_routing_numbers.py';
COMMENT ON COLUMN teller.routing_numbers.ach IS 'The account''s routing number for ACH transactions';
COMMENT ON COLUMN teller.routing_numbers.wire IS 'The account''s wire routing number';
COMMENT ON COLUMN teller.routing_numbers.bacs IS 'The account''s BACS sort code'; 