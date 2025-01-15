-- Disable triggers to avoid audit logs during cleanup
SET session_replication_role = 'replica';

-- Drop schema and all objects
DROP SCHEMA IF EXISTS teller CASCADE;

-- Drop roles
DROP USER IF EXISTS teller;
DROP ROLE IF EXISTS teller_admin;
DROP ROLE IF EXISTS teller_write;
DROP ROLE IF EXISTS teller_read;

-- Drop database (must be run from another database)
\c postgres
DROP DATABASE IF EXISTS prod; 