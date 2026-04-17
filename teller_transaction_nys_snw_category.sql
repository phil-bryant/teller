CREATE TABLE teller.transaction_nys_snw_category (
    transaction_id TEXT NOT NULL REFERENCES teller.transaction(transaction_id),
    nys_snw_category_id BIGINT NOT NULL REFERENCES teller.nys_snw_category(nys_snw_category_id),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);
COMMENT ON TABLE teller.transaction_nys_snw_category IS 'Table for classifying transactions';
COMMENT ON COLUMN teller.transaction_nys_snw_category.transaction_id IS 'Reference to the id of the transaction';
COMMENT ON COLUMN teller.transaction_nys_snw_category.transaction_id IS 'Reference to the id of the category';