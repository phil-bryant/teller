-- Script to transfer ownership of tables from postgres to teller user
DO
$$
DECLARE
    r RECORD;
BEGIN
    -- Grant ownership of all tables to teller
    FOR r IN 
        SELECT 
            tablename,
            schemaname 
        FROM 
            pg_tables 
        WHERE 
            schemaname = 'public' 
            OR schemaname = 'teller'
    LOOP
        EXECUTE format('ALTER TABLE %I.%I OWNER TO teller', 
                      r.schemaname, 
                      r.tablename);
    END LOOP;
    
    -- Grant ownership of all sequences to teller
    FOR r IN 
        SELECT 
            sequencename,
            schemaname 
        FROM 
            pg_sequences 
        WHERE 
            schemaname = 'public' 
            OR schemaname = 'teller'
    LOOP
        EXECUTE format('ALTER SEQUENCE %I.%I OWNER TO teller', 
                      r.schemaname, 
                      r.sequencename);
    END LOOP;
    
    -- Grant ownership of all views to teller
    FOR r IN 
        SELECT 
            viewname,
            schemaname 
        FROM 
            pg_views 
        WHERE 
            schemaname = 'public' 
            OR schemaname = 'teller'
    LOOP
        EXECUTE format('ALTER VIEW %I.%I OWNER TO teller', 
                      r.schemaname, 
                      r.viewname);
    END LOOP;
    
    -- Grant ownership of all functions to teller
    -- Use pg_get_function_identity_arguments to get the exact function signature
    FOR r IN 
        SELECT 
            p.proname AS function_name,
            n.nspname AS schema_name,
            pg_get_function_identity_arguments(p.oid) AS function_args
        FROM 
            pg_proc p
            JOIN pg_namespace n ON p.pronamespace = n.oid
        WHERE 
            (n.nspname = 'public' OR n.nspname = 'teller')
    LOOP
        -- Use the proper function signature with arguments
        IF r.function_args = '' THEN
            -- Function without arguments
            EXECUTE format('ALTER FUNCTION %I.%I() OWNER TO teller', 
                          r.schema_name, 
                          r.function_name);
        ELSE
            -- Function with arguments
            EXECUTE format('ALTER FUNCTION %I.%I(%s) OWNER TO teller', 
                          r.schema_name, 
                          r.function_name,
                          r.function_args);
        END IF;
    END LOOP;
END;
$$; 