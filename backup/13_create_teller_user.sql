-- Create teller user with login ability
CREATE USER teller WITH PASSWORD 'secure_password_here';

-- Transfer schema ownership
ALTER SCHEMA teller OWNER TO teller;

-- Transfer ownership of all objects in teller schema
DO $$
DECLARE
    r RECORD;
BEGIN
    -- Tables
    FOR r IN SELECT tablename FROM pg_tables WHERE schemaname = 'teller'
    LOOP
        EXECUTE format('ALTER TABLE teller.%I OWNER TO teller', r.tablename);
    END LOOP;
    
    -- Sequences
    FOR r IN SELECT sequencename FROM pg_sequences WHERE schemaname = 'teller'
    LOOP
        EXECUTE format('ALTER SEQUENCE teller.%I OWNER TO teller', r.sequencename);
    END LOOP;
    
    -- Types
    FOR r IN SELECT typname FROM pg_type t 
        JOIN pg_namespace n ON t.typnamespace = n.oid 
        WHERE n.nspname = 'teller' AND t.typtype = 'e'
    LOOP
        EXECUTE format('ALTER TYPE teller.%I OWNER TO teller', r.typname);
    END LOOP;
    
    -- Functions
    FOR r IN SELECT proname, oid FROM pg_proc p 
        JOIN pg_namespace n ON p.pronamespace = n.oid 
        WHERE n.nspname = 'teller'
    LOOP
        EXECUTE format('ALTER FUNCTION teller.%I(%s) OWNER TO teller', 
            r.proname,
            pg_get_function_identity_arguments(r.oid));
    END LOOP;
END $$;

-- Verify ownership
SELECT n.nspname as schema,
       c.relname as name,
       CASE c.relkind 
           WHEN 'r' THEN 'table'
           WHEN 'S' THEN 'sequence'
           WHEN 'v' THEN 'view'
           WHEN 'f' THEN 'foreign table'
       END as type,
       r.rolname as owner
FROM pg_class c
JOIN pg_roles r ON c.relowner = r.oid
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname = 'teller'
ORDER BY c.relkind, c.relname; 