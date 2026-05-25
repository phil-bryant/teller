DO $$ BEGIN
    CREATE TYPE teller.transaction_categorization_method AS ENUM ('user', 'ai');
    COMMENT ON TYPE teller.transaction_categorization_method IS 'How was a transaction classified: manually by the user or automatically via ai';
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

CREATE TABLE IF NOT EXISTS teller.transaction_nys_snw_category (
    transaction_id TEXT PRIMARY KEY REFERENCES teller.transaction(transaction_id) ON DELETE CASCADE,
    nys_snw_category_id BIGINT NOT NULL REFERENCES teller.nys_snw_category(nys_snw_category_id),
    type teller.transaction_categorization_method NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);
COMMENT ON TABLE teller.transaction_nys_snw_category IS 'Table for storing transaction (re)classifications';
COMMENT ON COLUMN teller.transaction_nys_snw_category.transaction_id IS 'Reference to the id of the transaction';
COMMENT ON COLUMN teller.transaction_nys_snw_category.nys_snw_category_id IS 'Reference to the id of the category';