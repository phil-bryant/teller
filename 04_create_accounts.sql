CREATE TABLE teller.accounts (
    id VARCHAR(50) PRIMARY KEY,
    enrollment_id VARCHAR(50) NOT NULL,
    institution_id VARCHAR(50) NOT NULL REFERENCES teller.institutions(id),
    name VARCHAR(100) NOT NULL,
    type account_type NOT NULL,
    subtype account_subtype NOT NULL,
    currency CHAR(3) NOT NULL,
    last_four CHAR(4) NOT NULL,
    status account_status NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);
COMMENT ON TABLE teller.accounts IS 'An Account represents an end-user''s individual financial account at a given financial institution.';
COMMENT ON COLUMN teller.accounts.id IS 'The id of the account itself';
COMMENT ON COLUMN teller.accounts.enrollment_id IS 'The id of the enrollment that the account belongs to';
COMMENT ON COLUMN teller.accounts.institution_id IS 'The internal Teller id assigned to the financial institution';
COMMENT ON COLUMN teller.accounts.name IS 'The account''s name';
COMMENT ON COLUMN teller.accounts.type IS 'The type of account. Either depository or credit';
COMMENT ON COLUMN teller.accounts.subtype IS 'The account''s subtype. For depository: checking, savings, money_market, certificate_of_deposit, treasury, sweep. For credit: credit_card';
COMMENT ON COLUMN teller.accounts.currency IS 'The ISO 4217 currency code of the account';
COMMENT ON COLUMN teller.accounts.last_four IS 'The last four digits of the account number';
COMMENT ON COLUMN teller.accounts.status IS 'The account''s status: open or closed. When closed it means that it''s closed from Teller''s perspective'; 