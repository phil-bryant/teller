-- Create production database owned by teller
CREATE DATABASE prod WITH 
    OWNER = teller
    ENCODING = 'UTF8'
    LC_COLLATE = 'en_US.UTF-8'
    LC_CTYPE = 'en_US.UTF-8'
    TEMPLATE = template0;

-- Connect to prod database to set up permissions
\c prod

-- Revoke public schema permissions
REVOKE CREATE ON SCHEMA public FROM PUBLIC;
REVOKE ALL ON ALL TABLES IN SCHEMA public FROM PUBLIC;

-- Create teller schema owned by teller user
CREATE SCHEMA IF NOT EXISTS teller AUTHORIZATION teller;

-- Verify database creation and ownership
\l+ prod

-- Verify schema creation and ownership
\dn+ teller 