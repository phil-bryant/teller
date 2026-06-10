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
        'human_overrode_ai_match'
    );
    COMMENT ON TYPE matchy.transaction_email_match_state IS 'Lifecycle state for transaction-to-email matching';
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
    CREATE TYPE matchy.transaction_email_match_selected_by AS ENUM ('ai', 'human');
    COMMENT ON TYPE matchy.transaction_email_match_selected_by IS 'Actor that selected a transaction-email match row';
EXCEPTION WHEN duplicate_object THEN NULL; END $$;
