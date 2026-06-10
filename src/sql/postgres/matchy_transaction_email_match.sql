CREATE TABLE IF NOT EXISTS matchy.transaction_email_match (
    match_id BIGSERIAL PRIMARY KEY,
    transaction_id TEXT NOT NULL REFERENCES teller.transaction(transaction_id) ON DELETE CASCADE,
    email_message_id TEXT,
    state matchy.transaction_email_match_state NOT NULL,
    ai_confidence DECIMAL(5,4) CHECK (ai_confidence IS NULL OR (ai_confidence >= 0 AND ai_confidence <= 1)),
    explanation_json JSONB NOT NULL DEFAULT '{}'::jsonb,
    selected_by matchy.transaction_email_match_selected_by NOT NULL,
    selected_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP,
    moved_to_matchy_at TIMESTAMP WITH TIME ZONE,
    active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
    ,
    CONSTRAINT chk_transaction_email_match_message_required
    CHECK (
        (state = 'ai_no_match_found' AND email_message_id IS NULL)
        OR (state <> 'ai_no_match_found' AND email_message_id IS NOT NULL)
    )
);

CREATE INDEX IF NOT EXISTS idx_transaction_email_match_transaction_id
    ON matchy.transaction_email_match(transaction_id);

CREATE INDEX IF NOT EXISTS idx_transaction_email_match_active_transaction_id
    ON matchy.transaction_email_match(transaction_id)
    WHERE active = TRUE;

CREATE INDEX IF NOT EXISTS idx_transaction_email_match_state
    ON matchy.transaction_email_match(state);

CREATE UNIQUE INDEX IF NOT EXISTS uq_transaction_email_match_email_active_non_override
    ON matchy.transaction_email_match(email_message_id)
    WHERE active = TRUE AND state <> 'human_overrode_ai_match';

CREATE OR REPLACE FUNCTION matchy.enforce_matchy_cardinality()
RETURNS TRIGGER AS $$
DECLARE
    conflicting_transaction_id TEXT;
BEGIN
    IF NEW.active IS TRUE
       AND NEW.state <> 'human_overrode_ai_match'
       AND NEW.email_message_id IS NOT NULL THEN
        SELECT transaction_id
          INTO conflicting_transaction_id
          FROM matchy.transaction_email_match m
         WHERE m.email_message_id = NEW.email_message_id
           AND m.active = TRUE
           AND m.state <> 'human_overrode_ai_match'
           AND m.match_id <> COALESCE(NEW.match_id, -1)
         LIMIT 1;

        IF conflicting_transaction_id IS NOT NULL THEN
            RAISE EXCEPTION 'email_message_id % is already actively matched to transaction %',
                NEW.email_message_id,
                conflicting_transaction_id
            USING ERRCODE = '23505';
        END IF;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS enforce_matchy_cardinality_trigger ON matchy.transaction_email_match;
CREATE TRIGGER enforce_matchy_cardinality_trigger
    BEFORE INSERT OR UPDATE ON matchy.transaction_email_match
    FOR EACH ROW
    EXECUTE FUNCTION matchy.enforce_matchy_cardinality();

COMMENT ON TABLE matchy.transaction_email_match IS 'Active and historical selected transaction-email links';
