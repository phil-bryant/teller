CREATE TABLE teller.identities (
    id BIGSERIAL PRIMARY KEY,
    account_id TEXT NOT NULL REFERENCES teller.accounts(id),
    type teller.identity_type NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);
COMMENT ON TABLE teller.identities IS 'Identity provides you with all of the accounts the end-user granted your application access authorization along with beneficial owner identity information for each of them';
COMMENT ON COLUMN teller.identities.type IS 'The type of identity: organization or person';

CREATE TABLE teller.addresses (
    id BIGSERIAL PRIMARY KEY,
    street TEXT NOT NULL,
    city TEXT NOT NULL,
    region TEXT NOT NULL,
    postal_code TEXT NOT NULL,
    country TEXT NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    UNIQUE (street, city, region, postal_code, country)
);
COMMENT ON TABLE teller.addresses IS 'Physical addresses that may be associated with one or more identities';
COMMENT ON COLUMN teller.addresses.street IS 'The street address';
COMMENT ON COLUMN teller.addresses.city IS 'The city name';
COMMENT ON COLUMN teller.addresses.region IS 'The region or state';
COMMENT ON COLUMN teller.addresses.postal_code IS 'The postal or zip code';
COMMENT ON COLUMN teller.addresses.country IS 'The ISO 3166-1 alpha-2 country code';

CREATE TABLE teller.identity_addresses (
    id BIGSERIAL PRIMARY KEY,
    identity_id BIGINT NOT NULL REFERENCES teller.identities(id),
    address_id BIGINT NOT NULL REFERENCES teller.addresses(id),
    is_primary BOOLEAN NOT NULL DEFAULT false,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);
COMMENT ON TABLE teller.identity_addresses IS 'Physical addresses associated with the identity';
COMMENT ON COLUMN teller.identity_addresses.is_primary IS 'Whether this is the primary address for the identity';

CREATE TABLE teller.identity_names (
    id BIGSERIAL PRIMARY KEY,
    identity_id BIGINT NOT NULL REFERENCES teller.identities(id),
    data TEXT NOT NULL,
    type teller.name_type NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);
COMMENT ON TABLE teller.identity_names IS 'Names associated with the identity';
COMMENT ON COLUMN teller.identity_names.data IS 'The name string';
COMMENT ON COLUMN teller.identity_names.type IS 'The type of name: name or alias';

CREATE TABLE teller.identity_phone_numbers (
    id BIGSERIAL PRIMARY KEY,
    identity_id BIGINT NOT NULL REFERENCES teller.identities(id),
    data TEXT NOT NULL,
    type teller.phone_type NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);
COMMENT ON TABLE teller.identity_phone_numbers IS 'Phone numbers associated with the identity';
COMMENT ON COLUMN teller.identity_phone_numbers.data IS 'The phone number';
COMMENT ON COLUMN teller.identity_phone_numbers.type IS 'The type of phone number: home, work, or mobile';

CREATE TABLE teller.identity_emails (
    id BIGSERIAL PRIMARY KEY,
    identity_id BIGINT NOT NULL REFERENCES teller.identities(id),
    data TEXT NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);
COMMENT ON TABLE teller.identity_emails IS 'Email addresses associated with the identity';
COMMENT ON COLUMN teller.identity_emails.data IS 'The email address'; 