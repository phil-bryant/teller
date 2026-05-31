SELECT pg_catalog.set_config('search_path', '', false);
REVOKE CREATE ON SCHEMA public FROM PUBLIC;
REVOKE ALL ON ALL TABLES IN SCHEMA public FROM PUBLIC;
DO $$ BEGIN CREATE ROLE teller_admin; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE ROLE teller_write; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE ROLE teller_read; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE ROLE teller_ingest_writer; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE ROLE teller_api_reader; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE ROLE teller_api_writer; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE ROLE teller_migration_admin; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
GRANT teller_read TO teller_write;
GRANT teller_write TO teller_admin;
GRANT teller_read TO teller_api_reader;
GRANT teller_write TO teller_api_writer;
GRANT teller_write TO teller_ingest_writer;
GRANT teller_admin TO teller_migration_admin;
SELECT format(
    'CREATE USER teller WITH PASSWORD %L NOSUPERUSER NOCREATEDB NOCREATEROLE INHERIT LOGIN CONNECTION LIMIT 100',
    :'teller_password'
)
WHERE NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'teller')
\gexec
SELECT format('ALTER USER teller WITH PASSWORD %L', :'teller_password')
WHERE EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'teller')
\gexec
GRANT teller_admin TO teller;
GRANT teller_api_reader TO teller;
GRANT teller_api_writer TO teller;
GRANT teller_ingest_writer TO teller;
GRANT teller_migration_admin TO teller;
CREATE SCHEMA IF NOT EXISTS teller AUTHORIZATION teller;
COMMENT ON SCHEMA teller IS 'Schema for persisting objects fetched from the teller.io API';
GRANT USAGE ON SCHEMA teller TO teller_read;
GRANT USAGE ON SCHEMA teller TO teller_write;
GRANT USAGE ON SCHEMA teller TO teller_api_reader;
GRANT USAGE ON SCHEMA teller TO teller_api_writer;
GRANT USAGE ON SCHEMA teller TO teller_ingest_writer;
GRANT USAGE ON SCHEMA teller TO teller_migration_admin;
GRANT ALL ON SCHEMA teller TO teller_admin;
ALTER DEFAULT PRIVILEGES FOR USER teller IN SCHEMA teller
    GRANT SELECT ON TABLES TO teller_read;
ALTER DEFAULT PRIVILEGES FOR USER teller IN SCHEMA teller
    GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO teller_write;
ALTER DEFAULT PRIVILEGES FOR USER teller IN SCHEMA teller
    GRANT SELECT ON TABLES TO teller_api_reader;
ALTER DEFAULT PRIVILEGES FOR USER teller IN SCHEMA teller
    GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO teller_api_writer;
ALTER DEFAULT PRIVILEGES FOR USER teller IN SCHEMA teller
    GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO teller_ingest_writer;
ALTER DEFAULT PRIVILEGES FOR USER teller IN SCHEMA teller
    GRANT USAGE ON SEQUENCES TO teller_write;
ALTER DEFAULT PRIVILEGES FOR USER teller IN SCHEMA teller
    GRANT USAGE ON SEQUENCES TO teller_api_writer;
ALTER DEFAULT PRIVILEGES FOR USER teller IN SCHEMA teller
    GRANT USAGE ON SEQUENCES TO teller_ingest_writer;
ALTER DEFAULT PRIVILEGES FOR USER teller IN SCHEMA teller
    GRANT ALL ON TABLES TO teller_admin;
ALTER DEFAULT PRIVILEGES FOR USER teller IN SCHEMA teller
    GRANT ALL ON TABLES TO teller_migration_admin;
ALTER DEFAULT PRIVILEGES FOR USER teller IN SCHEMA teller
    GRANT ALL ON SEQUENCES TO teller_admin;
ALTER DEFAULT PRIVILEGES FOR USER teller IN SCHEMA teller
    GRANT ALL ON SEQUENCES TO teller_migration_admin;
ALTER DEFAULT PRIVILEGES FOR USER teller IN SCHEMA teller
    GRANT ALL ON FUNCTIONS TO teller_admin;
ALTER DEFAULT PRIVILEGES FOR USER teller IN SCHEMA teller
    GRANT ALL ON FUNCTIONS TO teller_migration_admin;
ALTER DEFAULT PRIVILEGES FOR USER teller IN SCHEMA teller
    GRANT ALL ON TYPES TO teller_admin;
ALTER DEFAULT PRIVILEGES FOR USER teller IN SCHEMA teller
    GRANT ALL ON TYPES TO teller_migration_admin;
ALTER USER teller SET search_path TO teller;
SELECT format('ALTER DATABASE %I OWNER TO %I', :'db_name', :'teller_user') \gexec
