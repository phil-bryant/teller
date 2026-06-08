-- R055: Ensure ingest runtime role can reconcile/prune stale transactions.
GRANT DELETE ON TABLE teller.transaction TO teller_write;
GRANT DELETE ON TABLE teller.transaction_links TO teller_write;
GRANT DELETE ON TABLE teller.transaction_details TO teller_write;
GRANT DELETE ON TABLE teller.transaction_details_counterparty TO teller_write;
GRANT DELETE ON TABLE teller.transaction TO teller_ingest_writer;
GRANT DELETE ON TABLE teller.transaction_links TO teller_ingest_writer;
GRANT DELETE ON TABLE teller.transaction_details TO teller_ingest_writer;
GRANT DELETE ON TABLE teller.transaction_details_counterparty TO teller_ingest_writer;

-- R055: Audit trigger writes must remain permitted during DELETE operations.
GRANT INSERT ON TABLE teller.audit_log TO teller_write;
GRANT INSERT ON TABLE teller.audit_log TO teller_ingest_writer;
GRANT INSERT ON TABLE teller.audit_log TO teller_api_writer;

-- Deterministic, normalized text helper for hash key material.
CREATE OR REPLACE FUNCTION teller.normalize_pii_text(p_input text)
RETURNS text
LANGUAGE SQL
IMMUTABLE
AS $$
    SELECT lower(btrim(COALESCE(p_input, '')));
$$;

CREATE OR REPLACE FUNCTION teller.mask_email(p_email text)
RETURNS text
LANGUAGE SQL
IMMUTABLE
AS $$
    SELECT CASE
        WHEN COALESCE(p_email, '') = '' THEN ''
        WHEN position('@' IN p_email) <= 1 THEN '***'
        ELSE left(split_part(p_email, '@', 1), 1) || '***@' || split_part(p_email, '@', 2)
    END;
$$;

CREATE OR REPLACE FUNCTION teller.mask_phone(p_phone text)
RETURNS text
LANGUAGE SQL
IMMUTABLE
AS $$
    SELECT CASE
        WHEN COALESCE(p_phone, '') = '' THEN ''
        WHEN char_length(regexp_replace(p_phone, '[^0-9]', '', 'g')) < 4 THEN '***'
        ELSE '***-***-' || right(regexp_replace(p_phone, '[^0-9]', '', 'g'), 4)
    END;
$$;

CREATE OR REPLACE FUNCTION teller.mask_account_number(p_number text)
RETURNS text
LANGUAGE SQL
IMMUTABLE
AS $$
    SELECT CASE
        WHEN COALESCE(p_number, '') = '' THEN ''
        WHEN char_length(p_number) <= 4 THEN '****'
        ELSE '****' || right(p_number, 4)
    END;
$$;

CREATE OR REPLACE FUNCTION teller.mask_address(
    p_street text,
    p_city text,
    p_region text,
    p_country text,
    p_postal_code text
)
RETURNS text
LANGUAGE SQL
IMMUTABLE
AS $$
    SELECT COALESCE(NULLIF(left(COALESCE(p_street, ''), 3), ''), '***')
        || '***, '
        || COALESCE(p_city, '')
        || ', '
        || COALESCE(p_region, '')
        || ' '
        || COALESCE(p_country, '')
        || ' '
        || CASE
            WHEN COALESCE(p_postal_code, '') = '' THEN ''
            WHEN char_length(p_postal_code) <= 2 THEN '**'
            ELSE left(p_postal_code, 2) || '***'
        END;
$$;

ALTER TABLE teller.account_details
    ADD COLUMN IF NOT EXISTS account_number_hash TEXT,
    ADD COLUMN IF NOT EXISTS account_number_masked TEXT;

ALTER TABLE teller.identity_email
    ADD COLUMN IF NOT EXISTS data_hash TEXT,
    ADD COLUMN IF NOT EXISTS data_masked TEXT;

ALTER TABLE teller.identity_phone_number
    ADD COLUMN IF NOT EXISTS data_hash TEXT,
    ADD COLUMN IF NOT EXISTS data_masked TEXT;

ALTER TABLE teller.identity_address_data
    ADD COLUMN IF NOT EXISTS address_hash TEXT,
    ADD COLUMN IF NOT EXISTS address_masked TEXT;

CREATE OR REPLACE FUNCTION teller.apply_pii_protection_columns()
RETURNS TRIGGER AS $$
BEGIN
    IF TG_TABLE_NAME = 'account_details' THEN
        NEW.account_number_hash := md5(teller.normalize_pii_text(NEW.account_number));
        NEW.account_number_masked := teller.mask_account_number(NEW.account_number);
    ELSIF TG_TABLE_NAME = 'identity_email' THEN
        NEW.data_hash := md5(teller.normalize_pii_text(NEW.data));
        NEW.data_masked := teller.mask_email(NEW.data);
    ELSIF TG_TABLE_NAME = 'identity_phone_number' THEN
        NEW.data_hash := md5(teller.normalize_pii_text(NEW.data));
        NEW.data_masked := teller.mask_phone(NEW.data);
    ELSIF TG_TABLE_NAME = 'identity_address_data' THEN
        NEW.address_hash := md5(teller.normalize_pii_text(concat_ws(
            '|',
            NEW.street,
            NEW.city,
            NEW.region,
            NEW.country,
            NEW.postal_code
        )));
        NEW.address_masked := teller.mask_address(
            NEW.street,
            NEW.city,
            NEW.region,
            NEW.country,
            NEW.postal_code
        );
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS protect_account_details_pii ON teller.account_details;
CREATE TRIGGER protect_account_details_pii
    BEFORE INSERT OR UPDATE ON teller.account_details
    FOR EACH ROW
    EXECUTE FUNCTION teller.apply_pii_protection_columns();

DROP TRIGGER IF EXISTS protect_identity_email_pii ON teller.identity_email;
CREATE TRIGGER protect_identity_email_pii
    BEFORE INSERT OR UPDATE ON teller.identity_email
    FOR EACH ROW
    EXECUTE FUNCTION teller.apply_pii_protection_columns();

DROP TRIGGER IF EXISTS protect_identity_phone_pii ON teller.identity_phone_number;
CREATE TRIGGER protect_identity_phone_pii
    BEFORE INSERT OR UPDATE ON teller.identity_phone_number
    FOR EACH ROW
    EXECUTE FUNCTION teller.apply_pii_protection_columns();

DROP TRIGGER IF EXISTS protect_identity_address_pii ON teller.identity_address_data;
CREATE TRIGGER protect_identity_address_pii
    BEFORE INSERT OR UPDATE ON teller.identity_address_data
    FOR EACH ROW
    EXECUTE FUNCTION teller.apply_pii_protection_columns();

UPDATE teller.account_details
SET account_number_hash = md5(teller.normalize_pii_text(account_number)),
    account_number_masked = teller.mask_account_number(account_number)
WHERE account_number_hash IS NULL OR account_number_masked IS NULL;

UPDATE teller.identity_email
SET data_hash = md5(teller.normalize_pii_text(data)),
    data_masked = teller.mask_email(data)
WHERE data_hash IS NULL OR data_masked IS NULL;

UPDATE teller.identity_phone_number
SET data_hash = md5(teller.normalize_pii_text(data)),
    data_masked = teller.mask_phone(data)
WHERE data_hash IS NULL OR data_masked IS NULL;

UPDATE teller.identity_address_data
SET address_hash = md5(teller.normalize_pii_text(concat_ws('|', street, city, region, country, postal_code))),
    address_masked = teller.mask_address(street, city, region, country, postal_code)
WHERE address_hash IS NULL OR address_masked IS NULL;

CREATE UNIQUE INDEX IF NOT EXISTS idx_account_details_account_number_hash
    ON teller.account_details(account_number_hash);
CREATE INDEX IF NOT EXISTS idx_identity_email_data_hash
    ON teller.identity_email(data_hash);
CREATE INDEX IF NOT EXISTS idx_identity_phone_number_data_hash
    ON teller.identity_phone_number(data_hash);
CREATE INDEX IF NOT EXISTS idx_identity_address_data_address_hash
    ON teller.identity_address_data(address_hash);

CREATE OR REPLACE VIEW teller.account_details_secure_v1 AS
SELECT
    account_id,
    account_number_masked AS account_number_masked,
    account_number_hash,
    account_details_links_id,
    routing_numbers_id,
    created_at,
    updated_at
FROM teller.account_details;

CREATE OR REPLACE VIEW teller.identity_email_secure_v1 AS
SELECT
    identity_email_id,
    identity_id,
    data_masked AS email_masked,
    data_hash,
    created_at,
    updated_at
FROM teller.identity_email;

CREATE OR REPLACE VIEW teller.identity_phone_number_secure_v1 AS
SELECT
    identity_phone_number_id,
    identity_id,
    type,
    data_masked AS phone_masked,
    data_hash,
    created_at,
    updated_at
FROM teller.identity_phone_number;

CREATE OR REPLACE VIEW teller.identity_address_data_secure_v1 AS
SELECT
    identity_address_data_id,
    address_masked,
    address_hash,
    created_at,
    updated_at
FROM teller.identity_address_data;

GRANT SELECT ON teller.account_details_secure_v1 TO teller_read, teller_api_reader;
GRANT SELECT ON teller.identity_email_secure_v1 TO teller_read, teller_api_reader;
GRANT SELECT ON teller.identity_phone_number_secure_v1 TO teller_read, teller_api_reader;
GRANT SELECT ON teller.identity_address_data_secure_v1 TO teller_read, teller_api_reader;

DO $$
DECLARE
    qualified_table text;
    table_schema text;
    table_name text;
BEGIN
    FOREACH qualified_table IN ARRAY ARRAY[
        'teller.transaction',
        'teller.account_details',
        'teller.identity_email',
        'teller.identity_phone_number',
        'teller.identity_address_data',
        'classy.transaction_nys_snw_category',
        'matchy.transaction_email_candidate',
        'matchy.transaction_email_match'
    ]
    LOOP
        table_schema := split_part(qualified_table, '.', 1);
        table_name := split_part(qualified_table, '.', 2);
        EXECUTE format('ALTER TABLE %I.%I ENABLE ROW LEVEL SECURITY;', table_schema, table_name);
        EXECUTE format('ALTER TABLE %I.%I FORCE ROW LEVEL SECURITY;', table_schema, table_name);

        EXECUTE format('DROP POLICY IF EXISTS secure_read_policy ON %I.%I;', table_schema, table_name);
        EXECUTE format(
            'CREATE POLICY secure_read_policy ON %I.%I FOR SELECT USING (
                current_user IN (
                    ''postgres'',
                    ''teller'',
                    ''teller_read'',
                    ''teller_write'',
                    ''teller_admin'',
                    ''teller_api_reader'',
                    ''teller_api_writer'',
                    ''teller_ingest_writer'',
                    ''teller_migration_admin'',
                    ''classy_read'',
                    ''classy_write'',
                    ''classy_admin'',
                    ''classy_api_reader'',
                    ''classy_api_writer'',
                    ''classy_migration_admin'',
                    ''matchy_read'',
                    ''matchy_write'',
                    ''matchy_admin'',
                    ''matchy_service_reader'',
                    ''matchy_service_writer'',
                    ''matchy_migration_admin''
                )
            );',
            table_schema,
            table_name
        );

        EXECUTE format('DROP POLICY IF EXISTS secure_write_policy ON %I.%I;', table_schema, table_name);
        EXECUTE format(
            'CREATE POLICY secure_write_policy ON %I.%I FOR ALL
             USING (
                current_user IN (
                    ''postgres'',
                    ''teller'',
                    ''teller_write'',
                    ''teller_admin'',
                    ''teller_api_writer'',
                    ''teller_ingest_writer'',
                    ''teller_migration_admin'',
                    ''classy_write'',
                    ''classy_admin'',
                    ''classy_api_writer'',
                    ''classy_migration_admin'',
                    ''matchy_write'',
                    ''matchy_admin'',
                    ''matchy_service_writer'',
                    ''matchy_migration_admin''
                )
             )
             WITH CHECK (
                current_user IN (
                    ''postgres'',
                    ''teller'',
                    ''teller_write'',
                    ''teller_admin'',
                    ''teller_api_writer'',
                    ''teller_ingest_writer'',
                    ''teller_migration_admin'',
                    ''classy_write'',
                    ''classy_admin'',
                    ''classy_api_writer'',
                    ''classy_migration_admin'',
                    ''matchy_write'',
                    ''matchy_admin'',
                    ''matchy_service_writer'',
                    ''matchy_migration_admin''
                )
             );',
            table_schema,
            table_name
        );
    END LOOP;
END;
$$;

GRANT SELECT ON TABLE teller.audit_log TO teller_read, teller_api_reader;
GRANT SELECT ON TABLE teller.security_event_log TO teller_read, teller_api_reader;
GRANT INSERT ON TABLE teller.security_event_log TO teller_write, teller_api_writer, teller_ingest_writer;
GRANT SELECT ON TABLE teller.audit_log_export_v1 TO teller_read, teller_api_reader;
GRANT EXECUTE ON FUNCTION teller.log_security_event(text, text, jsonb) TO teller_write, teller_api_writer, teller_ingest_writer;
GRANT EXECUTE ON FUNCTION teller.purge_audit_log_before(TIMESTAMP WITH TIME ZONE, BOOLEAN) TO teller_admin, teller_migration_admin;
