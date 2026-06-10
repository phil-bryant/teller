DO $$ BEGIN
    CREATE TYPE classy.transaction_categorization_method AS ENUM ('user', 'ai');
    COMMENT ON TYPE classy.transaction_categorization_method IS 'How was a transaction classified: manually by the user or automatically via ai';
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

CREATE TABLE IF NOT EXISTS classy.transaction_nys_snw_category (
    transaction_id TEXT PRIMARY KEY REFERENCES teller.transaction(transaction_id) ON DELETE CASCADE,
    nys_snw_category_id BIGINT NOT NULL REFERENCES classy.nys_snw_category(nys_snw_category_id),
    type classy.transaction_categorization_method NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);
COMMENT ON TABLE classy.transaction_nys_snw_category IS 'Table for storing transaction (re)classifications';
COMMENT ON COLUMN classy.transaction_nys_snw_category.transaction_id IS 'Reference to the id of the transaction';
COMMENT ON COLUMN classy.transaction_nys_snw_category.nys_snw_category_id IS 'Reference to the id of the category';