CREATE OR REPLACE FUNCTION teller.update_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DO $$
DECLARE
    table_name text;
    trigger_name text;
BEGIN
    FOR table_name IN
        SELECT tables.table_name
        FROM information_schema.tables tables
        JOIN information_schema.columns columns
            ON columns.table_schema = tables.table_schema
            AND columns.table_name = tables.table_name
        WHERE tables.table_schema = 'teller'
            AND tables.table_type = 'BASE TABLE'
            AND columns.column_name = 'updated_at'
        ORDER BY tables.table_name
    LOOP
        trigger_name := format('update_%s_updated_at', table_name);
        IF EXISTS (
            SELECT 1
            FROM pg_trigger trg
            JOIN pg_class rel
                ON rel.oid = trg.tgrelid
            JOIN pg_namespace rel_ns
                ON rel_ns.oid = rel.relnamespace
            WHERE rel_ns.nspname = 'teller'
                AND rel.relname = table_name
                AND trg.tgname = trigger_name
                AND trg.tgisinternal = false
        ) THEN
            EXECUTE format(
                'DROP TRIGGER %I ON teller.%I;',
                trigger_name,
                table_name
            );
        END IF;
        EXECUTE format(
            'CREATE TRIGGER %I
                BEFORE UPDATE ON teller.%I
                FOR EACH ROW
                EXECUTE FUNCTION teller.update_updated_at();',
            trigger_name,
            table_name
        );
    END LOOP;
END;
$$;