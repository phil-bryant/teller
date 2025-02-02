CREATE TABLE teller.transaction_links (
    id BIGSERIAL PRIMARY KEY,
    self_link TEXT NOT NULL,
    account TEXT NOT NULL,
    transaction_id TEXT NOT NULL REFERENCES teller.transaction(id),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);
COMMENT ON TABLE teller.transaction_links IS 'Links associated with a transaction';
COMMENT ON COLUMN teller.transaction_links.self_link IS 'A self link to the transaction';
COMMENT ON COLUMN teller.transaction_links.account IS 'Link to the associated account'; 