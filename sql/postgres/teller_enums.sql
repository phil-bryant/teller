DO $$ BEGIN
    CREATE TYPE teller.account_type AS ENUM ('depository', 'credit');
    COMMENT ON TYPE teller.account_type IS 'The type of account. Either depository or credit';
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
    CREATE TYPE teller.account_subtype AS ENUM ('checking', 'savings', 'money_market', 'certificate_of_deposit', 'treasury', 'sweep', 'credit_card');
    COMMENT ON TYPE teller.account_subtype IS 'The account''s subtype. For depository: checking, savings, money_market, certificate_of_deposit, treasury, sweep. For credit: credit_card';
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
    CREATE TYPE teller.account_status AS ENUM ('open', 'closed');
    COMMENT ON TYPE teller.account_status IS 'The account''s status: open or closed. When closed it means that it''s closed from Teller''s perspective';
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
    CREATE TYPE teller.processing_status AS ENUM ('pending', 'complete');
    COMMENT ON TYPE teller.processing_status IS 'Indicates the transaction enrichment processing status. Either pending or complete';
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
    CREATE TYPE teller.transaction_status AS ENUM ('posted', 'pending');
    COMMENT ON TYPE teller.transaction_status IS 'The transaction''s status: posted or pending';
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
    CREATE TYPE teller.counterparty_type AS ENUM ('organization', 'person');
    COMMENT ON TYPE teller.counterparty_type IS 'The counterparty type: organization or person';
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
    CREATE TYPE teller.identity_type AS ENUM ('organization', 'person');
    COMMENT ON TYPE teller.identity_type IS 'The type of identity: organization or person';
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
    CREATE TYPE teller.identity_phone_number_type AS ENUM ('home', 'work', 'mobile', 'unknown');
    COMMENT ON TYPE teller.identity_phone_number_type IS 'The type of phone number associated with an identity: home, work, mobile, or unknown';
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
    CREATE TYPE teller.identity_name_type AS ENUM ('name', 'alias');
    COMMENT ON TYPE teller.identity_name_type IS 'The type of name associated with an identity: name or alias';
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
    CREATE TYPE teller.transaction_category AS ENUM (
        'accommodation', 'advertising', 'bar', 'charity', 'clothing',
        'dining', 'education', 'electronics', 'entertainment', 'fuel',
        'general', 'groceries', 'health', 'home', 'income', 'insurance',
        'investment', 'loan', 'office', 'phone', 'service', 'shopping',
        'software', 'sport', 'tax', 'transport', 'transportation', 'utilities'
    );
    COMMENT ON TYPE teller.transaction_category IS 'The category that the transaction belongs to. Teller uses the following values for categorization: accommodation, advertising, bar, charity, clothing, dining, education, electronics, entertainment, fuel, general, groceries, health, home, income, insurance, investment, loan, office, phone, service, shopping, software, sport, tax, transport, transportation, and utilities';
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
    CREATE TYPE teller.matchy_trigger_source AS ENUM ('auto', 'manual', 'retry');
    COMMENT ON TYPE teller.matchy_trigger_source IS 'Source that triggered a matchy matching run';
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
    CREATE TYPE teller.matchy_run_status AS ENUM ('succeeded', 'failed', 'no_candidates', 'needs_review');
    COMMENT ON TYPE teller.matchy_run_status IS 'Outcome status for a matchy run';
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
    CREATE TYPE teller.transaction_email_match_state AS ENUM (
        'ai_no_match_found',
        'ai_candidate_uncertain',
        'ai_match_confident',
        'human_confirmed_ai_match',
        'human_overrode_ai_match'
    );
    COMMENT ON TYPE teller.transaction_email_match_state IS 'Lifecycle state for transaction-to-email matching';
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
    CREATE TYPE teller.transaction_email_match_selected_by AS ENUM ('ai', 'human');
    COMMENT ON TYPE teller.transaction_email_match_selected_by IS 'Actor that selected a transaction-email match row';
EXCEPTION WHEN duplicate_object THEN NULL; END $$;
