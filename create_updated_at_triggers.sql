CREATE OR REPLACE PROCEDURE teller.create_updated_at_triggers(p_schema_name TEXT)
LANGUAGE plpgsql
AS $$
DECLARE
    table_record RECORD;
    schema_exists BOOLEAN;
BEGIN
    -- Check if schema exists
    SELECT EXISTS(
        SELECT 1 FROM information_schema.schemata 
        WHERE information_schema.schemata.schema_name = p_schema_name
    ) INTO schema_exists;
    
    -- Create schema if it doesn't exist
    IF NOT schema_exists THEN
        EXECUTE format('CREATE SCHEMA %I;', p_schema_name);
        RAISE NOTICE 'Created schema %', p_schema_name;
    END IF;
    
    -- Create the update_updated_at function in the specified schema
    EXECUTE format('
        CREATE OR REPLACE FUNCTION %I.update_updated_at()
        RETURNS TRIGGER AS $func$
        BEGIN
            NEW.updated_at = CURRENT_TIMESTAMP;
            RETURN NEW;
        END;
        $func$ LANGUAGE plpgsql;
    ', p_schema_name);
    
    -- Temporarily set client_min_messages to warning to suppress notices about non-existent triggers
    SET LOCAL client_min_messages TO warning;
    
    FOR table_record IN
        SELECT t.table_name
        FROM information_schema.tables t
        JOIN information_schema.columns c ON c.table_name = t.table_name AND c.table_schema = t.table_schema
        WHERE t.table_schema = p_schema_name
        AND c.column_name = 'updated_at'
        AND t.table_type = 'BASE TABLE'
    LOOP
        EXECUTE format('
            DROP TRIGGER IF EXISTS update_%s_updated_at ON %I.%I;
            CREATE TRIGGER update_%s_updated_at
            BEFORE UPDATE ON %I.%I
            FOR EACH ROW
            EXECUTE FUNCTION %I.update_updated_at();',
            table_record.table_name, p_schema_name, table_record.table_name, 
            table_record.table_name, p_schema_name, table_record.table_name,
            p_schema_name
        );
    END LOOP;
    
    -- Reset client_min_messages to default
    RESET client_min_messages;
END;
$$;

CALL teller.create_updated_at_triggers('teller');