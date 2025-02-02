CREATE TABLE teller.address_data (
    id BIGSERIAL PRIMARY KEY,
    postal_code TEXT NOT NULL,
    street TEXT NOT NULL,
    region TEXT NOT NULL,
    country TEXT NOT NULL,
    city TEXT NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);
COMMENT ON TABLE teller.address_data IS 'Physical address data associated with an identity';
COMMENT ON COLUMN teller.address_data.postal_code IS 'The postal or zip code';
COMMENT ON COLUMN teller.address_data.street IS 'The street address';
COMMENT ON COLUMN teller.address_data.region IS 'The region or state';
COMMENT ON COLUMN teller.address_data.country IS 'The ISO 3166-1 alpha-2 country code';
COMMENT ON COLUMN teller.address_data.city IS 'The city name'; 