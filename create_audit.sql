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

CREATE OR REPLACE FUNCTION teller.audit_trigger_func()
RETURNS TRIGGER AS $$
DECLARE
    record_pk TEXT;
    pk_columns text[];
    pk_val text;
    col text;
BEGIN
    pk_columns := teller.get_primary_key_columns(TG_TABLE_NAME);
    
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

DO $$ 
DECLARE
    table_name text;
BEGIN
    FOR table_name IN 
        SELECT tables.table_name 
        FROM information_schema.tables tables
        WHERE table_schema = 'teller' 
        AND table_type = 'BASE TABLE'
        AND table_name != 'audit_log'
    LOOP
        EXECUTE format('
            CREATE TRIGGER audit_%I
                AFTER INSERT OR UPDATE OR DELETE ON teller.%I
                FOR EACH ROW EXECUTE FUNCTION teller.audit_trigger_func();',
            table_name, table_name
        );
    END LOOP;
END;
$$; 