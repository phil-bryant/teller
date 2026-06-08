-- #R001: Provide a shared trigger function that sets updated_at on row updates.
CREATE OR REPLACE FUNCTION teller.update_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- #R005: Attach updated_at triggers to every product-schema base table that exposes updated_at.
DO $$
DECLARE
    schema_name text;
    table_name text;
    trigger_name text;
BEGIN
    FOR schema_name IN
        SELECT unnest(ARRAY['teller', 'classy', 'matchy'])
    LOOP
        -- #R010: Discover trigger targets from information_schema for deterministic coverage.
        FOR table_name IN
            SELECT tables.table_name
            FROM information_schema.tables tables
            JOIN information_schema.columns columns
                ON columns.table_schema = tables.table_schema
                AND columns.table_name = tables.table_name
            WHERE tables.table_schema = schema_name
                AND tables.table_type = 'BASE TABLE'
                AND columns.column_name = 'updated_at'
            ORDER BY tables.table_name
        LOOP
            trigger_name := format('update_%s_updated_at', table_name);
            -- #R015: Replace existing non-internal trigger definitions to keep deployment idempotent.
            IF EXISTS (
                SELECT 1
                FROM pg_trigger trg
                JOIN pg_class rel
                    ON rel.oid = trg.tgrelid
                JOIN pg_namespace rel_ns
                    ON rel_ns.oid = rel.relnamespace
                WHERE rel_ns.nspname = schema_name
                    AND rel.relname = table_name
                    AND trg.tgname = trigger_name
                    AND trg.tgisinternal = false
            ) THEN
                EXECUTE format(
                    'DROP TRIGGER %I ON %I.%I;',
                    trigger_name,
                    schema_name,
                    table_name
                );
            END IF;
            -- #R020: Create BEFORE UPDATE trigger namespaced per table using update_updated_at().
            EXECUTE format(
                'CREATE TRIGGER %I
                    BEFORE UPDATE ON %I.%I
                    FOR EACH ROW
                    EXECUTE FUNCTION teller.update_updated_at();',
                trigger_name,
                schema_name,
                table_name
            );
        END LOOP;
    END LOOP;
END;
$$;