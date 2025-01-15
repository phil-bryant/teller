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
BEGIN
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
            OLD.id::TEXT,
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
            OLD.id::TEXT,
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
            NEW.id::TEXT,
            TG_OP,
            to_jsonb(NEW)
        );
        RETURN NEW;
    END IF;
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

-- Core tables
CREATE TRIGGER institutions_audit
    AFTER INSERT OR UPDATE OR DELETE ON teller.institutions
    FOR EACH ROW
    EXECUTE FUNCTION teller.audit_trigger_func();

CREATE TRIGGER accounts_audit
    AFTER INSERT OR UPDATE OR DELETE ON teller.accounts
    FOR EACH ROW
    EXECUTE FUNCTION teller.audit_trigger_func();

CREATE TRIGGER account_details_audit
    AFTER INSERT OR UPDATE OR DELETE ON teller.account_details
    FOR EACH ROW
    EXECUTE FUNCTION teller.audit_trigger_func();

CREATE TRIGGER account_balances_audit
    AFTER INSERT OR UPDATE OR DELETE ON teller.account_balances
    FOR EACH ROW
    EXECUTE FUNCTION teller.audit_trigger_func();

-- Identity related tables
CREATE TRIGGER identities_audit
    AFTER INSERT OR UPDATE OR DELETE ON teller.identities
    FOR EACH ROW
    EXECUTE FUNCTION teller.audit_trigger_func();

CREATE TRIGGER addresses_audit
    AFTER INSERT OR UPDATE OR DELETE ON teller.addresses
    FOR EACH ROW
    EXECUTE FUNCTION teller.audit_trigger_func();

CREATE TRIGGER identity_addresses_audit
    AFTER INSERT OR UPDATE OR DELETE ON teller.identity_addresses
    FOR EACH ROW
    EXECUTE FUNCTION teller.audit_trigger_func();

CREATE TRIGGER identity_names_audit
    AFTER INSERT OR UPDATE OR DELETE ON teller.identity_names
    FOR EACH ROW
    EXECUTE FUNCTION teller.audit_trigger_func();

CREATE TRIGGER identity_phone_numbers_audit
    AFTER INSERT OR UPDATE OR DELETE ON teller.identity_phone_numbers
    FOR EACH ROW
    EXECUTE FUNCTION teller.audit_trigger_func();

CREATE TRIGGER identity_emails_audit
    AFTER INSERT OR UPDATE OR DELETE ON teller.identity_emails
    FOR EACH ROW
    EXECUTE FUNCTION teller.audit_trigger_func();

-- Links tables
CREATE TRIGGER account_links_audit
    AFTER INSERT OR UPDATE OR DELETE ON teller.account_links
    FOR EACH ROW
    EXECUTE FUNCTION teller.audit_trigger_func();

CREATE TRIGGER account_detail_links_audit
    AFTER INSERT OR UPDATE OR DELETE ON teller.account_detail_links
    FOR EACH ROW
    EXECUTE FUNCTION teller.audit_trigger_func();

CREATE TRIGGER account_balance_links_audit
    AFTER INSERT OR UPDATE OR DELETE ON teller.account_balance_links
    FOR EACH ROW
    EXECUTE FUNCTION teller.audit_trigger_func();

CREATE TRIGGER transaction_links_audit
    AFTER INSERT OR UPDATE OR DELETE ON teller.transaction_links
    FOR EACH ROW
    EXECUTE FUNCTION teller.audit_trigger_func();

-- Transaction related tables
CREATE TRIGGER transactions_audit
    AFTER INSERT OR UPDATE OR DELETE ON teller.transactions
    FOR EACH ROW
    EXECUTE FUNCTION teller.audit_trigger_func();

CREATE TRIGGER transaction_counterparties_audit
    AFTER INSERT OR UPDATE OR DELETE ON teller.transaction_counterparties
    FOR EACH ROW
    EXECUTE FUNCTION teller.audit_trigger_func(); 