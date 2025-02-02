CREATE TABLE teller.audit_log (
    id BIGSERIAL PRIMARY KEY,
    table_name TEXT NOT NULL,
    record_id TEXT NOT NULL,
    action TEXT NOT NULL CHECK (action IN ('INSERT', 'UPDATE', 'DELETE')),
    old_data JSONB,
    new_data JSONB,
    changed_by TEXT DEFAULT CURRENT_USER,
    changed_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE OR REPLACE FUNCTION teller.audit_trigger_func()
RETURNS TRIGGER AS $$
DECLARE
    record_pk TEXT;
BEGIN
    -- Determine the primary key value based on the table
    CASE TG_TABLE_NAME
    WHEN 'balances' THEN
        record_pk := NEW.account_id::TEXT;
    WHEN 'account_details' THEN
        record_pk := NEW.account_id::TEXT;
    WHEN 'account_links' THEN
        record_pk := NEW.account_id::TEXT;
    WHEN 'account_details_links' THEN
        record_pk := NEW.account_id::TEXT;
    WHEN 'account_balances_links' THEN
        record_pk := NEW.account_id::TEXT;
    WHEN 'transaction_links' THEN
        record_pk := NEW.transaction_id::TEXT;
    ELSE
        record_pk := NEW.id::TEXT;
    END CASE;

    IF TG_OP = 'UPDATE' THEN
        INSERT INTO teller.audit_log (
            table_name,
            record_id,
            action,
            old_data,
            new_data
        )
        VALUES (
            TG_TABLE_NAME::TEXT,
            record_pk,
            TG_OP,
            to_jsonb(OLD),
            to_jsonb(NEW)
        );
        RETURN NEW;
    ELSIF TG_OP = 'DELETE' THEN
        INSERT INTO teller.audit_log (
            table_name,
            record_id,
            action,
            old_data
        )
        VALUES (
            TG_TABLE_NAME::TEXT,
            record_pk,
            TG_OP,
            to_jsonb(OLD)
        );
        RETURN OLD;
    ELSIF TG_OP = 'INSERT' THEN
        INSERT INTO teller.audit_log (
            table_name,
            record_id,
            action,
            new_data
        )
        VALUES (
            TG_TABLE_NAME::TEXT,
            record_pk,
            TG_OP,
            to_jsonb(NEW)
        );
        RETURN NEW;
    END IF;
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

-- Create audit triggers for all tables
CREATE TRIGGER audit_institutions
    AFTER INSERT OR UPDATE OR DELETE ON teller.institutions
    FOR EACH ROW EXECUTE FUNCTION teller.audit_trigger_func();

CREATE TRIGGER audit_account
    AFTER INSERT OR UPDATE OR DELETE ON teller.account
    FOR EACH ROW EXECUTE FUNCTION teller.audit_trigger_func();

CREATE TRIGGER audit_balances
    AFTER INSERT OR UPDATE OR DELETE ON teller.balances
    FOR EACH ROW EXECUTE FUNCTION teller.audit_trigger_func();

CREATE TRIGGER audit_transaction
    AFTER INSERT OR UPDATE OR DELETE ON teller.transaction
    FOR EACH ROW EXECUTE FUNCTION teller.audit_trigger_func();

-- Add similar audit triggers for all other tables... 