DO $$ BEGIN
    CREATE TYPE matchy.matchy_trigger_source AS ENUM ('auto', 'manual', 'retry');
    COMMENT ON TYPE matchy.matchy_trigger_source IS 'Source that triggered a matchy matching run';
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
    CREATE TYPE matchy.matchy_run_status AS ENUM ('succeeded', 'failed', 'no_candidates', 'needs_review');
    COMMENT ON TYPE matchy.matchy_run_status IS 'Outcome status for a matchy run';
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
    CREATE TYPE matchy.transaction_email_match_state AS ENUM (
        'ai_no_match_found',
        'ai_candidate_uncertain',
        'ai_match_confident',
        'human_confirmed_ai_match',
        'human_overrode_ai_match',
        'human_matched'
    );
    COMMENT ON TYPE matchy.transaction_email_match_state IS 'Lifecycle state for transaction-to-email matching';
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- Idempotent forward-migration for already-deployed databases whose enum predates
-- the multi-select Match flow. 'human_matched' marks a human-linked email for a
-- transaction that never had an AI pick (vs human_overrode_ai_match, which implies AI).
ALTER TYPE matchy.transaction_email_match_state ADD VALUE IF NOT EXISTS 'human_matched';

DO $$ BEGIN
    CREATE TYPE matchy.transaction_email_match_selected_by AS ENUM ('ai', 'human');
    COMMENT ON TYPE matchy.transaction_email_match_selected_by IS 'Actor that selected a transaction-email match row';
EXCEPTION WHEN duplicate_object THEN NULL; END $$;
