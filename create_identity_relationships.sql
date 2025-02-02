CREATE TABLE teller.identity_addresses (
    identity_id BIGINT REFERENCES teller.identity(id),
    address_id BIGINT REFERENCES teller.address(id),
    PRIMARY KEY (identity_id, address_id)
);

CREATE TABLE teller.identity_names (
    identity_id BIGINT REFERENCES teller.identity(id),
    name_id BIGINT REFERENCES teller.name(id),
    PRIMARY KEY (identity_id, name_id)
);

CREATE TABLE teller.identity_phone_numbers (
    identity_id BIGINT REFERENCES teller.identity(id),
    phone_number_id BIGINT REFERENCES teller.phone_number(id),
    PRIMARY KEY (identity_id, phone_number_id)
);

CREATE TABLE teller.identity_emails (
    identity_id BIGINT REFERENCES teller.identity(id),
    email_id BIGINT REFERENCES teller.email(id),
    PRIMARY KEY (identity_id, email_id)
);
