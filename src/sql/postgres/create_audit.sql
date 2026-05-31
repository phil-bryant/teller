-- #R001: Persist immutable audit entries for row-level data changes.
CREATE TABLE IF NOT EXISTS teller.audit_log (
    id BIGSERIAL PRIMARY KEY,
    table_name TEXT NOT NULL,
    record_id TEXT NOT NULL,
    action TEXT NOT NULL CHECK (action IN ('INSERT', 'UPDATE', 'DELETE')),
    old_data JSONB,
    new_data JSONB,
    changed_by TEXT DEFAULT CURRENT_USER,
    changed_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

ALTER TABLE teller.audit_log
    ADD COLUMN IF NOT EXISTS request_id TEXT,
    ADD COLUMN IF NOT EXISTS actor_id TEXT,
    ADD COLUMN IF NOT EXISTS actor_service TEXT,
    ADD COLUMN IF NOT EXISTS session_role TEXT DEFAULT CURRENT_USER,
    ADD COLUMN IF NOT EXISTS app_context JSONB DEFAULT '{}'::jsonb;

-- #R005: Resolve ordered primary-key column names for a target table.
CREATE OR REPLACE FUNCTION teller.get_primary_key_columns(p_table_name text, p_schema_name text DEFAULT 'teller')
RETURNS text[] AS $$
    SELECT ARRAY_AGG(kcu.column_name::text ORDER BY kcu.ordinal_position)
    FROM information_schema.table_constraints tc
    JOIN information_schema.key_column_usage kcu 
        ON tc.constraint_name = kcu.constraint_name 
        AND tc.table_schema = kcu.table_schema
    WHERE tc.constraint_type = 'PRIMARY KEY'
        AND tc.table_name = p_table_name
        AND tc.table_schema = p_schema_name;
$$ LANGUAGE SQL STABLE;

-- #R010: Record INSERT/UPDATE/DELETE events with operation-specific old/new JSON payloads.
CREATE OR REPLACE FUNCTION teller.audit_trigger_func()
RETURNS TRIGGER AS $$
DECLARE
    record_pk TEXT;
    pk_columns text[];
    pk_val text;
    col text;
    request_id_value text;
    actor_id_value text;
    actor_service_value text;
BEGIN
    request_id_value := current_setting('teller.request_id', true);
    actor_id_value := current_setting('teller.actor_id', true);
    actor_service_value := current_setting('teller.actor_service', true);
    pk_columns := teller.get_primary_key_columns(TG_TABLE_NAME);
    
    -- #R015: Normalize record identifiers for single-column and composite primary keys.
    IF array_length(pk_columns, 1) = 1 THEN
        EXECUTE format('SELECT ($1.%I)::text', pk_columns[1])
        USING COALESCE(NEW, OLD)
        INTO record_pk;
    ELSE
        record_pk := '{';
        FOREACH col IN ARRAY pk_columns LOOP
            EXECUTE format('SELECT ($1.%I)::text', col)
            USING COALESCE(NEW, OLD)
            INTO pk_val;
            
            record_pk := record_pk || pk_val || ',';
        END LOOP;
        record_pk := rtrim(record_pk, ',') || '}';
    END IF;

    IF TG_OP = 'UPDATE' THEN
        INSERT INTO teller.audit_log (
            table_name,
            record_id,
            action,
            old_data,
            new_data,
            request_id,
            actor_id,
            actor_service,
            session_role,
            app_context
        )
        VALUES (
            TG_TABLE_NAME::TEXT,
            record_pk,
            TG_OP,
            to_jsonb(OLD),
            to_jsonb(NEW),
            request_id_value,
            actor_id_value,
            actor_service_value,
            current_user,
            jsonb_build_object(
                'txid', txid_current(),
                'schema', TG_TABLE_SCHEMA,
                'table', TG_TABLE_NAME
            )
        );
        RETURN NEW;
    ELSIF TG_OP = 'DELETE' THEN
        INSERT INTO teller.audit_log (
            table_name,
            record_id,
            action,
            old_data,
            request_id,
            actor_id,
            actor_service,
            session_role,
            app_context
        )
        VALUES (
            TG_TABLE_NAME::TEXT,
            record_pk,
            TG_OP,
            to_jsonb(OLD),
            request_id_value,
            actor_id_value,
            actor_service_value,
            current_user,
            jsonb_build_object(
                'txid', txid_current(),
                'schema', TG_TABLE_SCHEMA,
                'table', TG_TABLE_NAME
            )
        );
        RETURN OLD;
    ELSIF TG_OP = 'INSERT' THEN
        INSERT INTO teller.audit_log (
            table_name,
            record_id,
            action,
            new_data,
            request_id,
            actor_id,
            actor_service,
            session_role,
            app_context
        )
        VALUES (
            TG_TABLE_NAME::TEXT,
            record_pk,
            TG_OP,
            to_jsonb(NEW),
            request_id_value,
            actor_id_value,
            actor_service_value,
            current_user,
            jsonb_build_object(
                'txid', txid_current(),
                'schema', TG_TABLE_SCHEMA,
                'table', TG_TABLE_NAME
            )
        );
        RETURN NEW;
    END IF;
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

-- #R020: Attach audit triggers to every teller base table except audit_log itself.
DO $$ 
DECLARE
    table_name text;
BEGIN
    FOR table_name IN 
        SELECT tables.table_name 
        FROM information_schema.tables tables
        WHERE table_schema = 'teller' 
        AND table_type = 'BASE TABLE'
        AND tables.table_name != 'audit_log'
    LOOP
        EXECUTE format('DROP TRIGGER IF EXISTS audit_%I ON teller.%I;', table_name, table_name);
        EXECUTE format('
            CREATE TRIGGER audit_%I
                AFTER INSERT OR UPDATE OR DELETE ON teller.%I
                FOR EACH ROW EXECUTE FUNCTION teller.audit_trigger_func();',
            table_name, table_name
        );
    END LOOP;
END;
$$; 

CREATE TABLE IF NOT EXISTS teller.security_event_log (
    security_event_id BIGSERIAL PRIMARY KEY,
    event_type TEXT NOT NULL,
    severity TEXT NOT NULL CHECK (severity IN ('info', 'warning', 'critical')),
    actor_id TEXT,
    actor_service TEXT,
    request_id TEXT,
    payload JSONB NOT NULL DEFAULT '{}'::jsonb,
    occurred_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE OR REPLACE FUNCTION teller.log_security_event(
    p_event_type text,
    p_severity text,
    p_payload jsonb DEFAULT '{}'::jsonb
)
RETURNS BIGINT AS $$
DECLARE
    inserted_id BIGINT;
BEGIN
    INSERT INTO teller.security_event_log (
        event_type,
        severity,
        actor_id,
        actor_service,
        request_id,
        payload
    )
    VALUES (
        p_event_type,
        p_severity,
        current_setting('teller.actor_id', true),
        current_setting('teller.actor_service', true),
        current_setting('teller.request_id', true),
        COALESCE(p_payload, '{}'::jsonb)
    )
    RETURNING security_event_id INTO inserted_id;

    RETURN inserted_id;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE VIEW teller.audit_log_export_v1 AS
SELECT
    id,
    table_name,
    record_id,
    action,
    old_data,
    new_data,
    changed_by,
    changed_at,
    request_id,
    actor_id,
    actor_service,
    session_role,
    app_context
FROM teller.audit_log
ORDER BY changed_at, id;

CREATE OR REPLACE FUNCTION teller.purge_audit_log_before(
    p_cutoff TIMESTAMP WITH TIME ZONE,
    p_allow_delete BOOLEAN DEFAULT FALSE
)
RETURNS BIGINT AS $$
DECLARE
    deleted_count BIGINT := 0;
BEGIN
    IF p_allow_delete IS DISTINCT FROM TRUE THEN
        RAISE EXCEPTION 'Audit log purge requires explicit p_allow_delete=true';
    END IF;

    DELETE FROM teller.audit_log
    WHERE changed_at < p_cutoff;

    GET DIAGNOSTICS deleted_count = ROW_COUNT;
    RETURN deleted_count;
END;
$$ LANGUAGE plpgsql;