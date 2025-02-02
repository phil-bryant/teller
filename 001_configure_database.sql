SELECT pg_catalog.set_config('search_path', '', false);
REVOKE CREATE ON SCHEMA public FROM PUBLIC;
REVOKE ALL ON ALL TABLES IN SCHEMA public FROM PUBLIC;
CREATE ROLE teller_admin;
CREATE ROLE teller_write;
CREATE ROLE teller_read;
GRANT teller_read TO teller_write;
GRANT teller_write TO teller_admin;
CREATE USER teller WITH 
    PASSWORD 'QkCV#KC*eA9BDRx'
    NOSUPERUSER
    NOCREATEDB
    NOCREATEROLE
    INHERIT
    LOGIN
    CONNECTION LIMIT 100;
GRANT teller_admin TO teller;
CREATE SCHEMA IF NOT EXISTS teller AUTHORIZATION teller;
COMMENT ON SCHEMA teller IS 'Schema for persisting objects fetched from the teller.io API';
GRANT USAGE ON SCHEMA teller TO teller_read;
GRANT USAGE ON SCHEMA teller TO teller_write;
GRANT ALL ON SCHEMA teller TO teller_admin;
ALTER DEFAULT PRIVILEGES FOR USER teller IN SCHEMA teller
    GRANT SELECT ON TABLES TO teller_read;
ALTER DEFAULT PRIVILEGES FOR USER teller IN SCHEMA teller
    GRANT SELECT, INSERT, UPDATE ON TABLES TO teller_write;
ALTER DEFAULT PRIVILEGES FOR USER teller IN SCHEMA teller
    GRANT USAGE ON SEQUENCES TO teller_write;
ALTER DEFAULT PRIVILEGES FOR USER teller IN SCHEMA teller
    GRANT ALL ON TABLES TO teller_admin;
ALTER DEFAULT PRIVILEGES FOR USER teller IN SCHEMA teller
    GRANT ALL ON SEQUENCES TO teller_admin;
ALTER DEFAULT PRIVILEGES FOR USER teller IN SCHEMA teller
    GRANT ALL ON FUNCTIONS TO teller_admin;
ALTER DEFAULT PRIVILEGES FOR USER teller IN SCHEMA teller
    GRANT ALL ON TYPES TO teller_admin;
ALTER USER teller SET search_path TO teller;
ALTER DATABASE prod OWNER TO teller; 