-- #R001: Enable foreign keys for SQLite parity with relational constraints.
PRAGMA foreign_keys = ON;

-- #R005: Core institution/account graph used by ingest + classification joins.
CREATE TABLE IF NOT EXISTS institution (
    institution_id TEXT PRIMARY KEY,
    name TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS account_links (
    account_links_id INTEGER PRIMARY KEY AUTOINCREMENT,
    self_link TEXT NOT NULL UNIQUE,
    details TEXT,
    balances TEXT,
    transactions TEXT
);

CREATE TABLE IF NOT EXISTS account (
    account_id TEXT PRIMARY KEY,
    currency TEXT NOT NULL,
    enrollment_id TEXT NOT NULL,
    institution_id TEXT NOT NULL REFERENCES institution(institution_id),
    last_four TEXT NOT NULL,
    account_links_id INTEGER NOT NULL REFERENCES account_links(account_links_id),
    name TEXT NOT NULL,
    type TEXT NOT NULL,
    subtype TEXT,
    status TEXT NOT NULL,
    created_at TEXT DEFAULT CURRENT_TIMESTAMP,
    updated_at TEXT DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS identity (
    identity_id INTEGER PRIMARY KEY AUTOINCREMENT,
    type TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS identity_name (
    identity_name_id INTEGER PRIMARY KEY AUTOINCREMENT,
    type TEXT NOT NULL,
    data TEXT NOT NULL,
    identity_id INTEGER NOT NULL REFERENCES identity(identity_id) ON DELETE CASCADE,
    UNIQUE(data, identity_id)
);

CREATE TABLE IF NOT EXISTS identity_email (
    identity_email_id INTEGER PRIMARY KEY AUTOINCREMENT,
    data TEXT NOT NULL UNIQUE,
    identity_id INTEGER NOT NULL REFERENCES identity(identity_id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS identity_phone_number (
    identity_phone_number_id INTEGER PRIMARY KEY AUTOINCREMENT,
    type TEXT NOT NULL,
    data TEXT NOT NULL,
    identity_id INTEGER NOT NULL REFERENCES identity(identity_id) ON DELETE CASCADE,
    UNIQUE(data, identity_id)
);

CREATE TABLE IF NOT EXISTS identity_address_data (
    identity_address_data_id INTEGER PRIMARY KEY AUTOINCREMENT,
    street TEXT,
    city TEXT,
    region TEXT,
    country TEXT,
    postal_code TEXT,
    UNIQUE(street, city, region, country, postal_code)
);

CREATE TABLE IF NOT EXISTS identity_address (
    identity_address_id INTEGER PRIMARY KEY AUTOINCREMENT,
    primary_address INTEGER NOT NULL DEFAULT 0,
    identity_address_data_id INTEGER NOT NULL REFERENCES identity_address_data(identity_address_data_id) ON DELETE CASCADE,
    identity_id INTEGER NOT NULL REFERENCES identity(identity_id) ON DELETE CASCADE,
    UNIQUE(identity_address_data_id, identity_id)
);

CREATE TABLE IF NOT EXISTS account_identities (
    account_id TEXT NOT NULL REFERENCES account(account_id) ON DELETE CASCADE,
    identity_id INTEGER NOT NULL REFERENCES identity(identity_id) ON DELETE CASCADE,
    PRIMARY KEY(account_id, identity_id)
);

CREATE TABLE IF NOT EXISTS account_balances_links (
    account_balances_links_id INTEGER PRIMARY KEY AUTOINCREMENT,
    self_link TEXT NOT NULL UNIQUE,
    account_link TEXT
);

CREATE TABLE IF NOT EXISTS account_balances (
    account_balances_id INTEGER PRIMARY KEY AUTOINCREMENT,
    account_id TEXT NOT NULL UNIQUE REFERENCES account(account_id) ON DELETE CASCADE,
    ledger NUMERIC,
    available NUMERIC,
    account_balances_links_id INTEGER REFERENCES account_balances_links(account_balances_links_id),
    created_at TEXT DEFAULT CURRENT_TIMESTAMP,
    updated_at TEXT DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS routing_numbers (
    routing_numbers_id INTEGER PRIMARY KEY AUTOINCREMENT,
    ach TEXT,
    wire TEXT
);

CREATE TABLE IF NOT EXISTS account_details_links (
    account_details_links_id INTEGER PRIMARY KEY AUTOINCREMENT,
    self_link TEXT NOT NULL UNIQUE,
    account TEXT
);

CREATE TABLE IF NOT EXISTS account_details (
    account_details_id INTEGER PRIMARY KEY AUTOINCREMENT,
    account_id TEXT NOT NULL UNIQUE REFERENCES account(account_id) ON DELETE CASCADE,
    account_number TEXT,
    routing_numbers_id INTEGER REFERENCES routing_numbers(routing_numbers_id),
    account_details_links_id INTEGER REFERENCES account_details_links(account_details_links_id),
    created_at TEXT DEFAULT CURRENT_TIMESTAMP,
    updated_at TEXT DEFAULT CURRENT_TIMESTAMP
);

-- #R010: Transaction + classification + match-review tables required by runtime API.
CREATE TABLE IF NOT EXISTS transaction_type (
    transaction_type_id INTEGER PRIMARY KEY AUTOINCREMENT,
    code TEXT NOT NULL UNIQUE
);

CREATE TABLE IF NOT EXISTS transaction_details_counterparty (
    transaction_details_counterparty_id INTEGER PRIMARY KEY AUTOINCREMENT,
    name TEXT NOT NULL,
    type TEXT NOT NULL,
    UNIQUE(name, type)
);

CREATE TABLE IF NOT EXISTS transaction_details (
    transaction_details_id INTEGER PRIMARY KEY AUTOINCREMENT,
    processing_status TEXT NOT NULL,
    category TEXT,
    transaction_details_counterparty_id INTEGER REFERENCES transaction_details_counterparty(transaction_details_counterparty_id),
    created_at TEXT DEFAULT CURRENT_TIMESTAMP,
    updated_at TEXT DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS transaction_links (
    transaction_links_id INTEGER PRIMARY KEY AUTOINCREMENT,
    self_link TEXT NOT NULL UNIQUE,
    account TEXT
);

CREATE TABLE IF NOT EXISTS "transaction" (
    transaction_id TEXT PRIMARY KEY,
    account_id TEXT NOT NULL REFERENCES account(account_id),
    amount NUMERIC NOT NULL,
    date TEXT NOT NULL,
    description TEXT NOT NULL,
    transaction_details_id INTEGER REFERENCES transaction_details(transaction_details_id),
    status TEXT NOT NULL,
    transaction_links_id INTEGER REFERENCES transaction_links(transaction_links_id),
    running_balance NUMERIC,
    transaction_type_id INTEGER REFERENCES transaction_type(transaction_type_id),
    created_at TEXT DEFAULT CURRENT_TIMESTAMP,
    updated_at TEXT DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS nys_snw_category (
    nys_snw_category_id INTEGER PRIMARY KEY AUTOINCREMENT,
    level_1 TEXT,
    level_1_name TEXT,
    level_2 TEXT,
    level_2_name TEXT,
    level_3 TEXT,
    level_4 TEXT,
    categorization TEXT,
    applicability TEXT,
    is_seed INTEGER NOT NULL DEFAULT 0,
    created_at TEXT DEFAULT CURRENT_TIMESTAMP,
    updated_at TEXT DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS transaction_nys_snw_category (
    transaction_id TEXT PRIMARY KEY REFERENCES "transaction"(transaction_id) ON DELETE CASCADE,
    nys_snw_category_id INTEGER REFERENCES nys_snw_category(nys_snw_category_id),
    type TEXT NOT NULL,
    created_at TEXT DEFAULT CURRENT_TIMESTAMP,
    updated_at TEXT DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS transaction_email_match_run (
    match_run_id INTEGER PRIMARY KEY AUTOINCREMENT,
    transaction_id TEXT NOT NULL REFERENCES "transaction"(transaction_id) ON DELETE CASCADE,
    started_at TEXT DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS transaction_email_candidate (
    candidate_id INTEGER PRIMARY KEY AUTOINCREMENT,
    match_run_id INTEGER NOT NULL REFERENCES transaction_email_match_run(match_run_id) ON DELETE CASCADE,
    email_message_id TEXT NOT NULL,
    score REAL,
    reason_json TEXT DEFAULT '{}',
    email_received_at TEXT,
    is_selected_by_ai INTEGER DEFAULT 0,
    is_unmatched_email_priority INTEGER DEFAULT 0,
    cached_subject TEXT,
    cached_sender TEXT,
    cached_snippet TEXT,
    cached_fetched_at TEXT,
    updated_at TEXT DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(match_run_id, email_message_id)
);

CREATE TABLE IF NOT EXISTS transaction_email_match (
    match_id INTEGER PRIMARY KEY AUTOINCREMENT,
    transaction_id TEXT NOT NULL REFERENCES "transaction"(transaction_id) ON DELETE CASCADE,
    email_message_id TEXT,
    state TEXT NOT NULL,
    ai_confidence REAL,
    selected_by TEXT NOT NULL,
    selected_at TEXT DEFAULT CURRENT_TIMESTAMP,
    moved_to_matchy_at TEXT,
    active INTEGER NOT NULL DEFAULT 1,
    updated_at TEXT DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS transaction_email_match_audit (
    match_audit_id INTEGER PRIMARY KEY AUTOINCREMENT,
    match_id INTEGER NOT NULL REFERENCES transaction_email_match(match_id) ON DELETE CASCADE,
    from_state TEXT,
    to_state TEXT NOT NULL,
    actor TEXT NOT NULL,
    note TEXT,
    created_at TEXT DEFAULT CURRENT_TIMESTAMP
);

-- #R015: Materialize transaction list view shape consumed by verification/runtime queries.
CREATE VIEW IF NOT EXISTS transaction_info_view AS
SELECT t.transaction_id,
       t.account_id,
       t.description,
       t.amount,
       t.date,
       t.status,
       n.nys_snw_category_id
  FROM "transaction" t
  LEFT JOIN transaction_nys_snw_category n ON n.transaction_id = t.transaction_id;
