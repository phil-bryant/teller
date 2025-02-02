CREATE TABLE teller.address_data (
    street TEXT NOT NULL,
    city TEXT NOT NULL,
    region TEXT NOT NULL,
    country TEXT NOT NULL,
    postal_code TEXT NOT NULL,
    id BIGSERIAL PRIMARY KEY,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    UNIQUE (street, city, region, country, postal_code)
);
COMMENT ON TABLE teller.address_data IS 'Table for teller_address_data.py';
COMMENT ON COLUMN teller.address_data.street IS 'The street address';
COMMENT ON COLUMN teller.address_data.city IS 'The city name';
COMMENT ON COLUMN teller.address_data.region IS 'The region or state';
COMMENT ON COLUMN teller.address_data.country IS 'The ISO 3166-1 alpha-2 country code';
COMMENT ON COLUMN teller.address_data.postal_code IS 'The postal or zip code'; 