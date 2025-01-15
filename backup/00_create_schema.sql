CREATE DATABASE prod WITH 
    OWNER = postgres           
    ENCODING = 'UTF8'        
    LC_COLLATE = 'en_US.UTF-8'  
    LC_CTYPE = 'en_US.UTF-8'   
    TEMPLATE = template0;
SELECT pg_catalog.set_config('search_path', '', false);
REVOKE CREATE ON SCHEMA public FROM PUBLIC;
REVOKE ALL ON ALL TABLES IN SCHEMA public FROM PUBLIC;
CREATE ROLE teller_admin;
CREATE ROLE teller_write;
CREATE ROLE teller_read;
GRANT teller_read TO teller_write;
GRANT teller_write TO teller_admin;
CREATE USER teller WITH 
    PASSWORD 'QkCV@KC*eA9BDRx'
    NOSUPERUSER
    NOCREATEDB
    NOCREATEROLE
    INHERIT
    LOGIN
    CONNECTION LIMIT 100;
GRANT teller_admin TO teller;
CREATE SCHEMA IF NOT EXISTS teller AUTHORIZATION teller;
COMMENT ON SCHEMA teller IS 'Schema for Teller banking data and operations';
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
SELECT r.rolname, r.rolsuper, r.rolinherit,
       r.rolcreaterole, r.rolcreatedb, r.rolcanlogin,
       r.rolconnlimit, r.rolvaliduntil
FROM pg_catalog.pg_roles r
WHERE r.rolname = 'teller';
SELECT n.nspname, pg_catalog.pg_get_userbyid(n.nspowner) as owner,
       pg_catalog.obj_description(n.oid, 'pg_namespace') as description
FROM pg_catalog.pg_namespace n
WHERE n.nspname = 'teller';

drop database prod;
drop user teller;
drop schema teller;
drop user teller;