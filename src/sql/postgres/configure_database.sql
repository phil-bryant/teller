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
DO $$ BEGIN CREATE ROLE classy_admin; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE ROLE classy_write; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE ROLE classy_read; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE ROLE classy_api_reader; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE ROLE classy_api_writer; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE ROLE classy_migration_admin; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE ROLE matchy_admin; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE ROLE matchy_write; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE ROLE matchy_read; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE ROLE matchy_service_reader; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE ROLE matchy_service_writer; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE ROLE matchy_migration_admin; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
GRANT teller_read TO teller_write;
GRANT teller_write TO teller_admin;
GRANT teller_read TO teller_api_reader;
GRANT teller_write TO teller_api_writer;
GRANT teller_write TO teller_ingest_writer;
GRANT teller_admin TO teller_migration_admin;
GRANT classy_read TO classy_write;
GRANT classy_write TO classy_admin;
GRANT classy_read TO classy_api_reader;
GRANT classy_write TO classy_api_writer;
GRANT classy_admin TO classy_migration_admin;
GRANT matchy_read TO matchy_write;
GRANT matchy_write TO matchy_admin;
GRANT matchy_read TO matchy_service_reader;
GRANT matchy_write TO matchy_service_writer;
GRANT matchy_admin TO matchy_migration_admin;
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
GRANT classy_admin TO teller;
GRANT classy_api_reader TO teller;
GRANT classy_api_writer TO teller;
GRANT classy_migration_admin TO teller;
GRANT matchy_admin TO teller;
GRANT matchy_service_reader TO teller;
GRANT matchy_service_writer TO teller;
GRANT matchy_migration_admin TO teller;
CREATE SCHEMA IF NOT EXISTS teller AUTHORIZATION teller;
COMMENT ON SCHEMA teller IS 'Schema for persisting objects fetched from the teller.io API';
CREATE SCHEMA IF NOT EXISTS classy AUTHORIZATION teller;
COMMENT ON SCHEMA classy IS 'Schema for classy classification and category product state.';
CREATE SCHEMA IF NOT EXISTS matchy AUTHORIZATION teller;
COMMENT ON SCHEMA matchy IS 'Schema for matchy run, candidate, match, and audit state.';
GRANT USAGE ON SCHEMA teller TO teller_read;
GRANT USAGE ON SCHEMA teller TO teller_write;
GRANT USAGE ON SCHEMA teller TO teller_api_reader;
GRANT USAGE ON SCHEMA teller TO teller_api_writer;
GRANT USAGE ON SCHEMA teller TO teller_ingest_writer;
GRANT USAGE ON SCHEMA teller TO teller_migration_admin;
GRANT USAGE ON SCHEMA teller TO classy_read;
GRANT USAGE ON SCHEMA teller TO classy_write;
GRANT USAGE ON SCHEMA teller TO classy_api_reader;
GRANT USAGE ON SCHEMA teller TO classy_api_writer;
GRANT USAGE ON SCHEMA teller TO classy_migration_admin;
GRANT USAGE ON SCHEMA teller TO matchy_read;
GRANT USAGE ON SCHEMA teller TO matchy_write;
GRANT USAGE ON SCHEMA teller TO matchy_service_reader;
GRANT USAGE ON SCHEMA teller TO matchy_service_writer;
GRANT USAGE ON SCHEMA teller TO matchy_migration_admin;
GRANT ALL ON SCHEMA teller TO teller_admin;
GRANT USAGE ON SCHEMA classy TO classy_read;
GRANT USAGE ON SCHEMA classy TO classy_write;
GRANT USAGE ON SCHEMA classy TO classy_api_reader;
GRANT USAGE ON SCHEMA classy TO classy_api_writer;
GRANT USAGE ON SCHEMA classy TO classy_migration_admin;
GRANT ALL ON SCHEMA classy TO classy_admin;
GRANT USAGE ON SCHEMA matchy TO matchy_read;
GRANT USAGE ON SCHEMA matchy TO matchy_write;
GRANT USAGE ON SCHEMA matchy TO matchy_service_reader;
GRANT USAGE ON SCHEMA matchy TO matchy_service_writer;
GRANT USAGE ON SCHEMA matchy TO matchy_migration_admin;
GRANT ALL ON SCHEMA matchy TO matchy_admin;
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
    GRANT SELECT ON TABLES TO classy_read;
ALTER DEFAULT PRIVILEGES FOR USER teller IN SCHEMA teller
    GRANT SELECT ON TABLES TO classy_write;
ALTER DEFAULT PRIVILEGES FOR USER teller IN SCHEMA teller
    GRANT SELECT ON TABLES TO classy_api_reader;
ALTER DEFAULT PRIVILEGES FOR USER teller IN SCHEMA teller
    GRANT SELECT ON TABLES TO classy_api_writer;
ALTER DEFAULT PRIVILEGES FOR USER teller IN SCHEMA teller
    GRANT SELECT ON TABLES TO classy_migration_admin;
ALTER DEFAULT PRIVILEGES FOR USER teller IN SCHEMA teller
    GRANT SELECT ON TABLES TO matchy_read;
ALTER DEFAULT PRIVILEGES FOR USER teller IN SCHEMA teller
    GRANT SELECT ON TABLES TO matchy_write;
ALTER DEFAULT PRIVILEGES FOR USER teller IN SCHEMA teller
    GRANT SELECT ON TABLES TO matchy_service_reader;
ALTER DEFAULT PRIVILEGES FOR USER teller IN SCHEMA teller
    GRANT SELECT ON TABLES TO matchy_service_writer;
ALTER DEFAULT PRIVILEGES FOR USER teller IN SCHEMA teller
    GRANT SELECT ON TABLES TO matchy_migration_admin;
ALTER DEFAULT PRIVILEGES FOR USER teller IN SCHEMA teller
    GRANT REFERENCES ON TABLES TO classy_write;
ALTER DEFAULT PRIVILEGES FOR USER teller IN SCHEMA teller
    GRANT REFERENCES ON TABLES TO classy_api_writer;
ALTER DEFAULT PRIVILEGES FOR USER teller IN SCHEMA teller
    GRANT REFERENCES ON TABLES TO classy_migration_admin;
ALTER DEFAULT PRIVILEGES FOR USER teller IN SCHEMA teller
    GRANT REFERENCES ON TABLES TO matchy_write;
ALTER DEFAULT PRIVILEGES FOR USER teller IN SCHEMA teller
    GRANT REFERENCES ON TABLES TO matchy_service_writer;
ALTER DEFAULT PRIVILEGES FOR USER teller IN SCHEMA teller
    GRANT REFERENCES ON TABLES TO matchy_migration_admin;
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
ALTER DEFAULT PRIVILEGES FOR USER teller IN SCHEMA classy
    GRANT SELECT ON TABLES TO classy_read;
ALTER DEFAULT PRIVILEGES FOR USER teller IN SCHEMA classy
    GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO classy_write;
ALTER DEFAULT PRIVILEGES FOR USER teller IN SCHEMA classy
    GRANT SELECT ON TABLES TO classy_api_reader;
ALTER DEFAULT PRIVILEGES FOR USER teller IN SCHEMA classy
    GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO classy_api_writer;
ALTER DEFAULT PRIVILEGES FOR USER teller IN SCHEMA classy
    GRANT USAGE ON SEQUENCES TO classy_write;
ALTER DEFAULT PRIVILEGES FOR USER teller IN SCHEMA classy
    GRANT USAGE ON SEQUENCES TO classy_api_writer;
ALTER DEFAULT PRIVILEGES FOR USER teller IN SCHEMA classy
    GRANT ALL ON TABLES TO classy_admin;
ALTER DEFAULT PRIVILEGES FOR USER teller IN SCHEMA classy
    GRANT ALL ON TABLES TO classy_migration_admin;
ALTER DEFAULT PRIVILEGES FOR USER teller IN SCHEMA classy
    GRANT ALL ON SEQUENCES TO classy_admin;
ALTER DEFAULT PRIVILEGES FOR USER teller IN SCHEMA classy
    GRANT ALL ON SEQUENCES TO classy_migration_admin;
ALTER DEFAULT PRIVILEGES FOR USER teller IN SCHEMA classy
    GRANT ALL ON FUNCTIONS TO classy_admin;
ALTER DEFAULT PRIVILEGES FOR USER teller IN SCHEMA classy
    GRANT ALL ON FUNCTIONS TO classy_migration_admin;
ALTER DEFAULT PRIVILEGES FOR USER teller IN SCHEMA classy
    GRANT ALL ON TYPES TO classy_admin;
ALTER DEFAULT PRIVILEGES FOR USER teller IN SCHEMA classy
    GRANT ALL ON TYPES TO classy_migration_admin;
ALTER DEFAULT PRIVILEGES FOR USER teller IN SCHEMA matchy
    GRANT SELECT ON TABLES TO matchy_read;
ALTER DEFAULT PRIVILEGES FOR USER teller IN SCHEMA matchy
    GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO matchy_write;
ALTER DEFAULT PRIVILEGES FOR USER teller IN SCHEMA matchy
    GRANT SELECT ON TABLES TO matchy_service_reader;
ALTER DEFAULT PRIVILEGES FOR USER teller IN SCHEMA matchy
    GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO matchy_service_writer;
ALTER DEFAULT PRIVILEGES FOR USER teller IN SCHEMA matchy
    GRANT USAGE ON SEQUENCES TO matchy_write;
ALTER DEFAULT PRIVILEGES FOR USER teller IN SCHEMA matchy
    GRANT USAGE ON SEQUENCES TO matchy_service_writer;
ALTER DEFAULT PRIVILEGES FOR USER teller IN SCHEMA matchy
    GRANT ALL ON TABLES TO matchy_admin;
ALTER DEFAULT PRIVILEGES FOR USER teller IN SCHEMA matchy
    GRANT ALL ON TABLES TO matchy_migration_admin;
ALTER DEFAULT PRIVILEGES FOR USER teller IN SCHEMA matchy
    GRANT ALL ON SEQUENCES TO matchy_admin;
ALTER DEFAULT PRIVILEGES FOR USER teller IN SCHEMA matchy
    GRANT ALL ON SEQUENCES TO matchy_migration_admin;
ALTER DEFAULT PRIVILEGES FOR USER teller IN SCHEMA matchy
    GRANT ALL ON FUNCTIONS TO matchy_admin;
ALTER DEFAULT PRIVILEGES FOR USER teller IN SCHEMA matchy
    GRANT ALL ON FUNCTIONS TO matchy_migration_admin;
ALTER DEFAULT PRIVILEGES FOR USER teller IN SCHEMA matchy
    GRANT ALL ON TYPES TO matchy_admin;
ALTER DEFAULT PRIVILEGES FOR USER teller IN SCHEMA matchy
    GRANT ALL ON TYPES TO matchy_migration_admin;
DO $$
BEGIN
    IF to_regclass('teller.transaction') IS NOT NULL
       AND to_regclass('teller.account') IS NOT NULL
       AND to_regclass('teller.transaction_type') IS NOT NULL
       AND to_regclass('teller.transaction_details') IS NOT NULL
       AND to_regclass('teller.transaction_details_counterparty') IS NOT NULL THEN
        GRANT SELECT ON TABLE teller.transaction, teller.account, teller.transaction_type, teller.transaction_details, teller.transaction_details_counterparty
            TO classy_read, classy_write, classy_api_reader, classy_api_writer, classy_migration_admin,
               matchy_read, matchy_write, matchy_service_reader, matchy_service_writer, matchy_migration_admin;
        GRANT REFERENCES ON TABLE teller.transaction
            TO classy_write, classy_api_writer, classy_migration_admin,
               matchy_write, matchy_service_writer, matchy_migration_admin;
    END IF;
END $$;
ALTER USER teller SET search_path TO teller, classy, matchy;
SELECT format('ALTER DATABASE %I OWNER TO %I', :'db_name', :'teller_user') \gexec
