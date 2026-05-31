-- #R001: Enable foreign keys for SQLite parity with relational constraints.
PRAGMA foreign_keys = ON;

-- #R005: Core institution/account graph used by ingest + classification joins.
CREATE TABLE IF NOT EXISTS institution (
    institution_id TEXT PRIMARY KEY,
    name TEXT NOT NULL UNIQUE,
    created_at TEXT DEFAULT CURRENT_TIMESTAMP,
    updated_at TEXT DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS account_links (
    self_link TEXT NOT NULL UNIQUE,
    details TEXT,
    balances TEXT,
    transactions TEXT,
    account_links_id INTEGER PRIMARY KEY AUTOINCREMENT,
    created_at TEXT DEFAULT CURRENT_TIMESTAMP,
    updated_at TEXT DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS account (
    currency TEXT NOT NULL,
    enrollment_id TEXT NOT NULL,
    account_id TEXT PRIMARY KEY,
    institution_id TEXT NOT NULL REFERENCES institution(institution_id),
    last_four TEXT NOT NULL,
    account_links_id INTEGER NOT NULL REFERENCES account_links(account_links_id),
    name TEXT NOT NULL,
    type TEXT NOT NULL,
    subtype TEXT NOT NULL,
    status TEXT NOT NULL,
    created_at TEXT DEFAULT CURRENT_TIMESTAMP,
    updated_at TEXT DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS identity (
    type TEXT NOT NULL,
    identity_id INTEGER PRIMARY KEY AUTOINCREMENT,
    created_at TEXT DEFAULT CURRENT_TIMESTAMP,
    updated_at TEXT DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS identity_name (
    type TEXT NOT NULL,
    data TEXT NOT NULL,
    identity_name_id INTEGER PRIMARY KEY AUTOINCREMENT,
    identity_id INTEGER NOT NULL REFERENCES identity(identity_id) ON DELETE CASCADE,
    created_at TEXT DEFAULT CURRENT_TIMESTAMP,
    updated_at TEXT DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(data, identity_id)
);

CREATE TABLE IF NOT EXISTS identity_email (
    data TEXT NOT NULL UNIQUE,
    identity_email_id INTEGER PRIMARY KEY AUTOINCREMENT,
    identity_id INTEGER NOT NULL REFERENCES identity(identity_id) ON DELETE CASCADE,
    created_at TEXT DEFAULT CURRENT_TIMESTAMP,
    updated_at TEXT DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS identity_phone_number (
    type TEXT NOT NULL,
    data TEXT NOT NULL,
    identity_phone_number_id INTEGER PRIMARY KEY AUTOINCREMENT,
    identity_id INTEGER NOT NULL REFERENCES identity(identity_id) ON DELETE CASCADE,
    created_at TEXT DEFAULT CURRENT_TIMESTAMP,
    updated_at TEXT DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(data, identity_id)
);

CREATE TABLE IF NOT EXISTS identity_address_data (
    street TEXT,
    city TEXT,
    region TEXT,
    country TEXT,
    postal_code TEXT,
    identity_address_data_id INTEGER PRIMARY KEY AUTOINCREMENT,
    created_at TEXT DEFAULT CURRENT_TIMESTAMP,
    updated_at TEXT DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(street, city, region, country, postal_code)
);

CREATE TABLE IF NOT EXISTS identity_address (
    primary_address INTEGER NOT NULL DEFAULT 0,
    identity_address_data_id INTEGER NOT NULL REFERENCES identity_address_data(identity_address_data_id) ON DELETE CASCADE,
    identity_address_id INTEGER PRIMARY KEY AUTOINCREMENT,
    identity_id INTEGER NOT NULL REFERENCES identity(identity_id) ON DELETE CASCADE,
    created_at TEXT DEFAULT CURRENT_TIMESTAMP,
    updated_at TEXT DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(identity_address_data_id, identity_id)
);

CREATE TABLE IF NOT EXISTS account_identities (
    account_id TEXT NOT NULL REFERENCES account(account_id) ON DELETE CASCADE,
    identity_id INTEGER NOT NULL REFERENCES identity(identity_id) ON DELETE CASCADE,
    account_identities_id INTEGER PRIMARY KEY AUTOINCREMENT,
    created_at TEXT DEFAULT CURRENT_TIMESTAMP,
    updated_at TEXT DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(account_id, identity_id)
);

CREATE TABLE IF NOT EXISTS account_balances_links (
    self_link TEXT NOT NULL UNIQUE,
    account_link TEXT NOT NULL UNIQUE,
    account_balances_links_id INTEGER PRIMARY KEY AUTOINCREMENT,
    created_at TEXT DEFAULT CURRENT_TIMESTAMP,
    updated_at TEXT DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS account_balances (
    account_id TEXT NOT NULL REFERENCES account(account_id) ON DELETE CASCADE,
    ledger INTEGER,
    account_balances_links_id INTEGER NOT NULL REFERENCES account_balances_links(account_balances_links_id),
    available INTEGER,
    account_balances_id INTEGER PRIMARY KEY AUTOINCREMENT,
    created_at TEXT DEFAULT CURRENT_TIMESTAMP,
    updated_at TEXT DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS routing_numbers (
    ach TEXT,
    wire TEXT,
    bacs TEXT,
    routing_numbers_id INTEGER PRIMARY KEY AUTOINCREMENT,
    created_at TEXT DEFAULT CURRENT_TIMESTAMP,
    updated_at TEXT DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS account_details_links (
    self_link TEXT NOT NULL UNIQUE,
    account TEXT NOT NULL UNIQUE,
    account_details_links_id INTEGER PRIMARY KEY AUTOINCREMENT,
    created_at TEXT DEFAULT CURRENT_TIMESTAMP,
    updated_at TEXT DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS account_details (
    account_id TEXT REFERENCES account(account_id) ON DELETE CASCADE,
    account_number TEXT PRIMARY KEY,
    account_details_links_id INTEGER NOT NULL REFERENCES account_details_links(account_details_links_id) UNIQUE,
    routing_numbers_id INTEGER REFERENCES routing_numbers(routing_numbers_id) UNIQUE,
    created_at TEXT DEFAULT CURRENT_TIMESTAMP,
    updated_at TEXT DEFAULT CURRENT_TIMESTAMP
);

-- #R010: Transaction + classification + match-review tables required by runtime API.
CREATE TABLE IF NOT EXISTS transaction_type (
    code TEXT NOT NULL UNIQUE,
    transaction_type_id INTEGER PRIMARY KEY AUTOINCREMENT,
    created_at TEXT DEFAULT CURRENT_TIMESTAMP,
    updated_at TEXT DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS transaction_details_counterparty (
    name TEXT NOT NULL,
    type TEXT NOT NULL,
    transaction_details_counterparty_id INTEGER PRIMARY KEY AUTOINCREMENT,
    created_at TEXT DEFAULT CURRENT_TIMESTAMP,
    updated_at TEXT DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS transaction_details (
    processing_status TEXT NOT NULL,
    category TEXT,
    transaction_details_counterparty_id INTEGER REFERENCES transaction_details_counterparty(transaction_details_counterparty_id),
    transaction_details_id INTEGER PRIMARY KEY AUTOINCREMENT,
    created_at TEXT DEFAULT CURRENT_TIMESTAMP,
    updated_at TEXT DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS transaction_links (
    self_link TEXT NOT NULL UNIQUE,
    account TEXT NOT NULL,
    transaction_links_id INTEGER PRIMARY KEY AUTOINCREMENT,
    created_at TEXT DEFAULT CURRENT_TIMESTAMP,
    updated_at TEXT DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS "transaction" (
    account_id TEXT NOT NULL REFERENCES account(account_id),
    amount INTEGER NOT NULL,
    date TEXT NOT NULL,
    description TEXT NOT NULL,
    transaction_details_id INTEGER NOT NULL UNIQUE REFERENCES transaction_details(transaction_details_id),
    status TEXT NOT NULL,
    transaction_id TEXT PRIMARY KEY,
    transaction_links_id INTEGER NOT NULL UNIQUE REFERENCES transaction_links(transaction_links_id),
    running_balance INTEGER,
    transaction_type_id INTEGER NOT NULL REFERENCES transaction_type(transaction_type_id),
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

INSERT OR IGNORE INTO nys_snw_category (
    nys_snw_category_id,
    level_1,
    level_1_name,
    level_2,
    level_2_name,
    level_3,
    level_4,
    categorization,
    applicability,
    is_seed
)
VALUES
    (1, 'II.', 'EXPENSES:', '(a)', 'Housing: Monthly', '1.', NULL, 'Mortgage/Co-op Loan', 'N/A', 1),
    (2, 'II.', 'EXPENSES:', '(a)', 'Housing: Monthly', '2.', NULL, 'Home Equity Line of Credit/Second Mortgage', 'N/A', 1),
    (3, 'II.', 'EXPENSES:', '(a)', 'Housing: Monthly', '3.', NULL, 'Real Estate Taxes', 'N/A', 1),
    (4, 'II.', 'EXPENSES:', '(a)', 'Housing: Monthly', '4.', NULL, 'Homeowners/Renter''s Insurance', 'N/A', 1),
    (5, 'II.', 'EXPENSES:', '(a)', 'Housing: Monthly', '5.', NULL, 'Homeowner''s Association/Maintenance charges/Condominium Charges', 'N/A', 1),
    (6, 'II.', 'EXPENSES:', '(a)', 'Housing: Monthly', '6.', NULL, 'Rent', NULL, 1),
    (7, 'II.', 'EXPENSES:', '(a)', 'Housing: Monthly', '7.', NULL, 'Other', 'N/A', 1),
    (8, 'II.', 'EXPENSES:', '(b)', 'Utilities:  Monthly', '1.', NULL, 'Fuel Oil/Gas', 'N/A', 1),
    (9, 'II.', 'EXPENSES:', '(b)', 'Utilities:  Monthly', '2.', NULL, 'Electric', 'N/A', 1),
    (10, 'II.', 'EXPENSES:', '(b)', 'Utilities:  Monthly', '3.', NULL, 'Telephone (land line)', 'N/A', 1),
    (11, 'II.', 'EXPENSES:', '(b)', 'Utilities:  Monthly', '4.', NULL, 'Mobile Phone', NULL, 1),
    (12, 'II.', 'EXPENSES:', '(b)', 'Utilities:  Monthly', '5.', NULL, 'Cable/Satellite TV', NULL, 1),
    (13, 'II.', 'EXPENSES:', '(b)', 'Utilities:  Monthly', '6.', NULL, 'Internet', NULL, 1),
    (14, 'II.', 'EXPENSES:', '(b)', 'Utilities:  Monthly', '7.', NULL, 'Alarm', 'N/A', 1),
    (15, 'II.', 'EXPENSES:', '(b)', 'Utilities:  Monthly', '8.', NULL, 'Water', 'N/A', 1),
    (16, 'II.', 'EXPENSES:', '(b)', 'Utilities:  Monthly', '9.', NULL, 'Other', NULL, 1),
    (17, 'II.', 'EXPENSES:', '(c)', 'Food: Monthly', '1.', NULL, 'Groceries', NULL, 1),
    (18, 'II.', 'EXPENSES:', '(c)', 'Food: Monthly', '2.', NULL, 'Dining Out/Take Out', NULL, 1),
    (19, 'II.', 'EXPENSES:', '(c)', 'Food: Monthly', '3.', NULL, 'Other', NULL, 1),
    (20, 'II.', 'EXPENSES:', '(d)', 'Clothing:  Monthly', '1.', NULL, 'Yourself', NULL, 1),
    (21, 'II.', 'EXPENSES:', '(d)', 'Clothing:  Monthly', '2.', NULL, 'Child(ren)', 'N/A', 1),
    (22, 'II.', 'EXPENSES:', '(d)', 'Clothing:  Monthly', '3.', NULL, 'Dry Cleaning', NULL, 1),
    (23, 'II.', 'EXPENSES:', '(d)', 'Clothing:  Monthly', '4.', NULL, 'Other', NULL, 1),
    (24, 'II.', 'EXPENSES:', '(e)', 'Insurance: Monthly', '1.', NULL, 'Life', 'N/A', 1),
    (25, 'II.', 'EXPENSES:', '(e)', 'Insurance: Monthly', '2.', NULL, 'Fire, theft and liability and personal articles policy', 'N/A', 1),
    (26, 'II.', 'EXPENSES:', '(e)', 'Insurance: Monthly', '3.', NULL, 'Automotive', 'N/A', 1),
    (27, 'II.', 'EXPENSES:', '(e)', 'Insurance: Monthly', '4.', NULL, 'Umbrella Policy', 'N/A', 1),
    (28, 'II.', 'EXPENSES:', '(e)', 'Insurance: Monthly', '5.', NULL, 'Medical Plan', NULL, 1),
    (29, 'II.', 'EXPENSES:', '(e)', 'Insurance: Monthly', '5.', 'A.', 'Medical Plan for yourself', NULL, 1),
    (30, 'II.', 'EXPENSES:', '(e)', 'Insurance: Monthly', '5.', 'B.', 'Medical Plan for children', 'N/A', 1),
    (31, 'II.', 'EXPENSES:', '(e)', 'Insurance: Monthly', '6.', NULL, 'Dental Plan', 'N/A', 1),
    (32, 'II.', 'EXPENSES:', '(e)', 'Insurance: Monthly', '7.', NULL, 'Optical Plan', 'N/A', 1),
    (33, 'II.', 'EXPENSES:', '(e)', 'Insurance: Monthly', '8.', NULL, 'Disability', 'N/A', 1),
    (34, 'II.', 'EXPENSES:', '(e)', 'Insurance: Monthly', '9.', NULL, 'Worker''s Compensation', 'N/A', 1),
    (35, 'II.', 'EXPENSES:', '(e)', 'Insurance: Monthly', '10.', NULL, 'Long Term Care Insurance', 'N/A', 1),
    (36, 'II.', 'EXPENSES:', '(e)', 'Insurance: Monthly', '11.', NULL, 'Other', 'N/A', 1),
    (37, 'II.', 'EXPENSES:', '(f)', 'Unreimbursed Medical:  Monthly', '1.', NULL, 'Medical', NULL, 1),
    (38, 'II.', 'EXPENSES:', '(f)', 'Unreimbursed Medical:  Monthly', '2.', NULL, 'Dental', NULL, 1),
    (39, 'II.', 'EXPENSES:', '(f)', 'Unreimbursed Medical:  Monthly', '3.', NULL, 'Optical', NULL, 1),
    (40, 'II.', 'EXPENSES:', '(f)', 'Unreimbursed Medical:  Monthly', '4.', NULL, 'Pharmaceutical', NULL, 1),
    (41, 'II.', 'EXPENSES:', '(f)', 'Unreimbursed Medical:  Monthly', '5.', NULL, 'Surgical, Nursing, Hospital', NULL, 1),
    (42, 'II.', 'EXPENSES:', '(f)', 'Unreimbursed Medical:  Monthly', '6.', NULL, 'Psychotherapy', NULL, 1),
    (43, 'II.', 'EXPENSES:', '(f)', 'Unreimbursed Medical:  Monthly', '7.', NULL, 'Other', 'N/A', 1),
    (44, 'II.', 'EXPENSES:', '(g)', 'Household Maintenance:  Monthly', '1.', NULL, 'Repairs/Maintenance', 'N/A', 1),
    (45, 'II.', 'EXPENSES:', '(g)', 'Household Maintenance:  Monthly', '2.', NULL, 'Gardening/landscaping', 'N/A', 1),
    (46, 'II.', 'EXPENSES:', '(g)', 'Household Maintenance:  Monthly', '3.', NULL, 'Sanitation/carting', 'N/A', 1),
    (47, 'II.', 'EXPENSES:', '(g)', 'Household Maintenance:  Monthly', '4.', NULL, 'Snow Removal', 'N/A', 1),
    (48, 'II.', 'EXPENSES:', '(g)', 'Household Maintenance:  Monthly', '5.', NULL, 'Extermination', 'N/A', 1),
    (49, 'II.', 'EXPENSES:', '(g)', 'Household Maintenance:  Monthly', '6.', NULL, 'Other', 'N/A', 1),
    (50, 'II.', 'EXPENSES:', '(h)', 'Household Help:  Monthly', '1.', NULL, 'Domestic (housekeeper, etc.)', 'N/A', 1),
    (51, 'II.', 'EXPENSES:', '(h)', 'Household Help:  Monthly', '2.', NULL, 'Nanny/Au Pair/Child Care', 'N/A', 1),
    (52, 'II.', 'EXPENSES:', '(h)', 'Household Help:  Monthly', '3.', NULL, 'Babysitter', 'N/A', 1),
    (53, 'II.', 'EXPENSES:', '(h)', 'Household Help:  Monthly', '4.', NULL, 'Other', 'N/A', 1),
    (54, 'II.', 'EXPENSES:', '(i)', 'Automobile:  Monthly', '1.', NULL, 'Lease or Loan Payments (indicate lease term)', 'N/A', 1),
    (55, 'II.', 'EXPENSES:', '(i)', 'Automobile:  Monthly', '2.', NULL, 'Gas and Oil', NULL, 1),
    (56, 'II.', 'EXPENSES:', '(i)', 'Automobile:  Monthly', '3.', NULL, 'Repairs', 'N/A', 1),
    (57, 'II.', 'EXPENSES:', '(i)', 'Automobile:  Monthly', '4.', NULL, 'Car Wash', 'N/A', 1),
    (58, 'II.', 'EXPENSES:', '(i)', 'Automobile:  Monthly', '5.', NULL, 'Parking and tolls', 'N/A', 1),
    (59, 'II.', 'EXPENSES:', '(i)', 'Automobile:  Monthly', '6.', NULL, 'Other', NULL, 1),
    (60, 'II.', 'EXPENSES:', '(j)', 'Education Costs:  Monthly', '1.', NULL, 'Nursery and Pre-school', 'N/A', 1),
    (61, 'II.', 'EXPENSES:', '(j)', 'Education Costs:  Monthly', '2.', NULL, 'Primary and Secondary', 'N/A', 1),
    (62, 'II.', 'EXPENSES:', '(j)', 'Education Costs:  Monthly', '3.', NULL, 'College', 'N/A', 1),
    (63, 'II.', 'EXPENSES:', '(j)', 'Education Costs:  Monthly', '4.', NULL, 'Post-Graduate', 'N/A', 1),
    (64, 'II.', 'EXPENSES:', '(j)', 'Education Costs:  Monthly', '5.', NULL, 'Religious Instruction', 'N/A', 1),
    (65, 'II.', 'EXPENSES:', '(j)', 'Education Costs:  Monthly', '6.', NULL, 'School Transportation', 'N/A', 1),
    (66, 'II.', 'EXPENSES:', '(j)', 'Education Costs:  Monthly', '7.', NULL, 'School Supplies/Books', 'N/A', 1),
    (67, 'II.', 'EXPENSES:', '(j)', 'Education Costs:  Monthly', '8.', NULL, 'School Lunches', 'N/A', 1),
    (68, 'II.', 'EXPENSES:', '(j)', 'Education Costs:  Monthly', '9.', NULL, 'Tutoring', 'N/A', 1),
    (69, 'II.', 'EXPENSES:', '(j)', 'Education Costs:  Monthly', '10.', NULL, 'School Events', 'N/A', 1),
    (70, 'II.', 'EXPENSES:', '(j)', 'Education Costs:  Monthly', '11.', NULL, 'Child(ren)''s extra-curricular and educational enrichment activities (Dance, Music, Sports, etc.)', 'N/A', 1),
    (71, 'II.', 'EXPENSES:', '(j)', 'Education Costs:  Monthly', '12.', NULL, 'Other', 'N/A', 1),
    (72, 'II.', 'EXPENSES:', '(k)', 'Recreational:  Monthly', '1.', NULL, 'Vacations', 'N/A', 1),
    (73, 'II.', 'EXPENSES:', '(k)', 'Recreational:  Monthly', '2.', NULL, 'Movies, Theatre, Ballet, Etc.', 'N/A', 1),
    (74, 'II.', 'EXPENSES:', '(k)', 'Recreational:  Monthly', '3.', NULL, 'Music (Digital or Physical Media)', NULL, 1),
    (75, 'II.', 'EXPENSES:', '(k)', 'Recreational:  Monthly', '4.', NULL, 'Recreation Clubs and Memberships', 'N/A', 1),
    (76, 'II.', 'EXPENSES:', '(k)', 'Recreational:  Monthly', '5.', NULL, 'Activities for yourself', 'N/A', 1),
    (77, 'II.', 'EXPENSES:', '(k)', 'Recreational:  Monthly', '6.', NULL, 'Health Club', 'N/A', 1),
    (78, 'II.', 'EXPENSES:', '(k)', 'Recreational:  Monthly', '7.', NULL, 'Summer Camp', 'N/A', 1),
    (79, 'II.', 'EXPENSES:', '(k)', 'Recreational:  Monthly', '8.', NULL, 'Birthday party costs for your child(ren)', 'N/A', 1),
    (80, 'II.', 'EXPENSES:', '(k)', 'Recreational:  Monthly', '9.', NULL, 'Other', 'N/A', 1),
    (81, 'II.', 'EXPENSES:', '(l)', 'Income Taxes:  Monthly', '1.', NULL, 'Federal', 'N/A', 1),
    (82, 'II.', 'EXPENSES:', '(l)', 'Income Taxes:  Monthly', '2.', NULL, 'State', 'N/A', 1),
    (83, 'II.', 'EXPENSES:', '(l)', 'Income Taxes:  Monthly', '3.', NULL, 'City', 'N/A', 1),
    (84, 'II.', 'EXPENSES:', '(l)', 'Income Taxes:  Monthly', '4.', NULL, 'Social Security and Medicare', 'N/A', 1),
    (85, 'II.', 'EXPENSES:', '(l)', 'Income Taxes:  Monthly', '5.', NULL, 'Number of dependents claimed in prior tax year', '0.', 1),
    (86, 'II.', 'EXPENSES:', '(l)', 'Income Taxes:  Monthly', '6.', NULL, 'List any refund received by you for prior tax year', NULL, 1),
    (87, 'II.', 'EXPENSES:', '(m)', 'Miscellaneous:  Monthly', '1.', NULL, 'Beauty parlor/Barber/Spa', NULL, 1),
    (88, 'II.', 'EXPENSES:', '(m)', 'Miscellaneous:  Monthly', '2.', NULL, 'Toiletries/Non-Prescription Drugs', NULL, 1),
    (89, 'II.', 'EXPENSES:', '(m)', 'Miscellaneous:  Monthly', '3.', NULL, 'Books, magazines, newspapers', NULL, 1),
    (90, 'II.', 'EXPENSES:', '(m)', 'Miscellaneous:  Monthly', '4.', NULL, 'Gifts to others', NULL, 1),
    (91, 'II.', 'EXPENSES:', '(m)', 'Miscellaneous:  Monthly', '5.', NULL, 'Charitable contributions', 'N/A', 1),
    (92, 'II.', 'EXPENSES:', '(m)', 'Miscellaneous:  Monthly', '6.', NULL, 'Religious organizations dues', 'N/A', 1),
    (93, 'II.', 'EXPENSES:', '(m)', 'Miscellaneous:  Monthly', '7.', NULL, 'Union and organization dues', 'N/A', 1),
    (94, 'II.', 'EXPENSES:', '(m)', 'Miscellaneous:  Monthly', '8.', NULL, 'Commutation expenses', 'N/A', 1),
    (95, 'II.', 'EXPENSES:', '(m)', 'Miscellaneous:  Monthly', '9.', NULL, 'Veterinarian/pet expenses', NULL, 1),
    (96, 'II.', 'EXPENSES:', '(m)', 'Miscellaneous:  Monthly', '10.', NULL, 'Child support payments (for Child(ren) of a prior marriage or relationship pursuant to court order or agreement)', 'N/A', 1),
    (97, 'II.', 'EXPENSES:', '(m)', 'Miscellaneous:  Monthly', '11.', NULL, 'Alimony and maintenance payments (prior marriage pursuant to court order or agreement)', 'N/A', 1),
    (98, 'II.', 'EXPENSES:', '(m)', 'Miscellaneous:  Monthly', '12.', NULL, 'Loan payments', 'N/A', 1),
    (99, 'II.', 'EXPENSES:', '(m)', 'Miscellaneous:  Monthly', '13.', NULL, 'Unreimbursed business expenses', NULL, 1),
    (100, 'II.', 'EXPENSES:', '(m)', 'Miscellaneous:  Monthly', '14.', NULL, 'Safe Deposit Box rental fee', 'N/A', 1),
    (101, 'II.', 'EXPENSES:', '(n)', 'Other:  Monthly', '1.', NULL, NULL, NULL, 1),
    (102, 'II.', 'EXPENSES:', '(n)', 'Other:  Monthly', '2.', NULL, NULL, NULL, 1),
    (103, 'II.', 'EXPENSES:', '(n)', 'Other:  Monthly', '3.', NULL, NULL, NULL, 1),
    (104, 'III.', 'GROSS INCOME INFORMATION:', '(a)', NULL, NULL, NULL, 'Gross (total) income - as should have been or should be reported in the most recent Federal income tax return.', NULL, 1),
    (105, 'III.', 'GROSS INCOME INFORMATION:', '(b)', 'To the extent not already included in gross income in (a) above:', '1.', NULL, 'Investment income, including interest and dividend income, reduced by sums expended in connection with such investment', NULL, 1),
    (106, 'III.', 'GROSS INCOME INFORMATION:', '(b)', 'To the extent not already included in gross income in (a) above:', '2.', NULL, 'Worker''s compensation (indicate percentage of amount due to lost wages)', 'N/A', 1),
    (107, 'III.', 'GROSS INCOME INFORMATION:', '(b)', 'To the extent not already included in gross income in (a) above:', '3.', NULL, 'Disability benefits (indicate percentage of amount due to lost wages)', 'N/A', 1),
    (108, 'III.', 'GROSS INCOME INFORMATION:', '(b)', 'To the extent not already included in gross income in (a) above:', '4.', NULL, 'Unemployment insurance benefits', 'N/A', 1),
    (109, 'III.', 'GROSS INCOME INFORMATION:', '(b)', 'To the extent not already included in gross income in (a) above:', '5.', NULL, 'Social Security benefits', 'N/A', 1),
    (110, 'III.', 'GROSS INCOME INFORMATION:', '(b)', 'To the extent not already included in gross income in (a) above:', '6.', NULL, 'Supplemental Security Income', 'N/A', 1),
    (111, 'III.', 'GROSS INCOME INFORMATION:', '(b)', 'To the extent not already included in gross income in (a) above:', '7.', NULL, 'Public assistance', 'N/A', 1),
    (112, 'III.', 'GROSS INCOME INFORMATION:', '(b)', 'To the extent not already included in gross income in (a) above:', '8.', NULL, 'Food stamps', 'N/A', 1),
    (113, 'III.', 'GROSS INCOME INFORMATION:', '(b)', 'To the extent not already included in gross income in (a) above:', '9.', NULL, 'Veterans benefits', 'N/A', 1),
    (114, 'III.', 'GROSS INCOME INFORMATION:', '(b)', 'To the extent not already included in gross income in (a) above:', '10.', NULL, 'Pensions and retirement benefits', 'N/A', 1),
    (115, 'III.', 'GROSS INCOME INFORMATION:', '(b)', 'To the extent not already included in gross income in (a) above:', '11.', NULL, 'Fellowships and stipends', 'N/A', 1),
    (116, 'III.', 'GROSS INCOME INFORMATION:', '(b)', 'To the extent not already included in gross income in (a) above:', '12.', NULL, 'Annuity payments', 'N/A', 1);

-- Align known punctuation/spacing variants with canonical Postgres seed text.
UPDATE nys_snw_category
   SET categorization = 'Homeowners/Renter’s Insurance'
 WHERE nys_snw_category_id = 4;
UPDATE nys_snw_category
   SET categorization = 'Homeowner’s Association/Maintenance charges/Condominium Charges'
 WHERE nys_snw_category_id = 5;
UPDATE nys_snw_category
   SET categorization = 'Worker’s Compensation'
 WHERE nys_snw_category_id = 34;
UPDATE nys_snw_category
   SET categorization = 'Child(ren)’s extra-curricular and educational enrichment activities (Dance, Music, Sports, etc.)'
 WHERE nys_snw_category_id = 70;
UPDATE nys_snw_category
   SET level_2_name = 'To the extent not already included in gross income in (a) above:',
       categorization = 'Worker’s compensation (indicate percentage of amount due to lost wages)'
 WHERE nys_snw_category_id = 106;

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
    trigger_source TEXT NOT NULL,
    model_name TEXT NOT NULL,
    prompt_version TEXT NOT NULL,
    status TEXT NOT NULL,
    started_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    completed_at TEXT,
    error_text TEXT,
    created_at TEXT DEFAULT CURRENT_TIMESTAMP,
    updated_at TEXT DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS transaction_email_candidate (
    candidate_id INTEGER PRIMARY KEY AUTOINCREMENT,
    match_run_id INTEGER NOT NULL REFERENCES transaction_email_match_run(match_run_id) ON DELETE CASCADE,
    transaction_id TEXT NOT NULL REFERENCES "transaction"(transaction_id) ON DELETE CASCADE,
    email_message_id TEXT NOT NULL,
    email_received_at TEXT,
    score REAL NOT NULL CHECK (score >= 0 AND score <= 1),
    reason_json TEXT NOT NULL DEFAULT '{}',
    is_unmatched_email_priority INTEGER NOT NULL DEFAULT 0,
    is_selected_by_ai INTEGER NOT NULL DEFAULT 0,
    cached_subject TEXT,
    cached_sender TEXT,
    cached_snippet TEXT,
    cached_fetched_at TEXT,
    created_at TEXT DEFAULT CURRENT_TIMESTAMP,
    updated_at TEXT DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(match_run_id, email_message_id)
);

CREATE TABLE IF NOT EXISTS transaction_email_match (
    match_id INTEGER PRIMARY KEY AUTOINCREMENT,
    transaction_id TEXT NOT NULL REFERENCES "transaction"(transaction_id) ON DELETE CASCADE,
    email_message_id TEXT,
    state TEXT NOT NULL,
    ai_confidence REAL,
    explanation_json TEXT NOT NULL DEFAULT '{}',
    selected_by TEXT NOT NULL,
    selected_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    moved_to_matchy_at TEXT,
    active INTEGER NOT NULL DEFAULT 1 CHECK (active IN (0, 1)),
    created_at TEXT DEFAULT CURRENT_TIMESTAMP,
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

-- #R010: Audit log table keeps SQLite table inventory aligned with PostgreSQL deploy.
CREATE TABLE IF NOT EXISTS audit_log (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    table_name TEXT NOT NULL,
    record_id TEXT NOT NULL,
    action TEXT NOT NULL CHECK (action IN ('INSERT', 'UPDATE', 'DELETE')),
    old_data TEXT,
    new_data TEXT,
    changed_by TEXT DEFAULT 'sqlite',
    changed_at TEXT DEFAULT CURRENT_TIMESTAMP
);

CREATE TRIGGER IF NOT EXISTS audit_institution_insert
AFTER INSERT ON institution
BEGIN
    INSERT INTO audit_log (table_name, record_id, action, new_data, changed_by, changed_at)
    VALUES ('institution', NEW.institution_id, 'INSERT',
            json_object('institution_id', NEW.institution_id, 'name', NEW.name, 'created_at', NEW.created_at, 'updated_at', NEW.updated_at),
            'teller_write', COALESCE(NEW.created_at, CURRENT_TIMESTAMP));
END;

CREATE TRIGGER IF NOT EXISTS audit_account_links_insert
AFTER INSERT ON account_links
BEGIN
    INSERT INTO audit_log (table_name, record_id, action, new_data, changed_by, changed_at)
    VALUES ('account_links', CAST(NEW.account_links_id AS TEXT), 'INSERT',
            json_object('account_links_id', NEW.account_links_id, 'self_link', NEW.self_link, 'details', NEW.details, 'balances', NEW.balances, 'transactions', NEW.transactions, 'created_at', NEW.created_at, 'updated_at', NEW.updated_at),
            'teller_write', COALESCE(NEW.created_at, CURRENT_TIMESTAMP));
END;

CREATE TRIGGER IF NOT EXISTS audit_account_insert
AFTER INSERT ON account
BEGIN
    INSERT INTO audit_log (table_name, record_id, action, new_data, changed_by, changed_at)
    VALUES ('account', NEW.account_id, 'INSERT',
            json_object('account_id', NEW.account_id, 'currency', NEW.currency, 'enrollment_id', NEW.enrollment_id, 'institution_id', NEW.institution_id, 'last_four', NEW.last_four, 'account_links_id', NEW.account_links_id, 'name', NEW.name, 'type', NEW.type, 'subtype', NEW.subtype, 'status', NEW.status, 'created_at', NEW.created_at, 'updated_at', NEW.updated_at),
            'teller_write', COALESCE(NEW.created_at, CURRENT_TIMESTAMP));
END;

CREATE TRIGGER IF NOT EXISTS audit_identity_insert
AFTER INSERT ON identity
BEGIN
    INSERT INTO audit_log (table_name, record_id, action, new_data, changed_by, changed_at)
    VALUES ('identity', CAST(NEW.identity_id AS TEXT), 'INSERT',
            json_object('identity_id', NEW.identity_id, 'type', NEW.type, 'created_at', NEW.created_at, 'updated_at', NEW.updated_at),
            'teller_write', COALESCE(NEW.created_at, CURRENT_TIMESTAMP));
END;

CREATE TRIGGER IF NOT EXISTS audit_identity_name_insert
AFTER INSERT ON identity_name
BEGIN
    INSERT INTO audit_log (table_name, record_id, action, new_data, changed_by, changed_at)
    VALUES ('identity_name', CAST(NEW.identity_name_id AS TEXT), 'INSERT',
            json_object('identity_name_id', NEW.identity_name_id, 'type', NEW.type, 'data', NEW.data, 'identity_id', NEW.identity_id, 'created_at', NEW.created_at, 'updated_at', NEW.updated_at),
            'teller_write', COALESCE(NEW.created_at, CURRENT_TIMESTAMP));
END;

CREATE TRIGGER IF NOT EXISTS audit_identity_email_insert
AFTER INSERT ON identity_email
BEGIN
    INSERT INTO audit_log (table_name, record_id, action, new_data, changed_by, changed_at)
    VALUES ('identity_email', CAST(NEW.identity_email_id AS TEXT), 'INSERT',
            json_object('identity_email_id', NEW.identity_email_id, 'data', NEW.data, 'identity_id', NEW.identity_id, 'created_at', NEW.created_at, 'updated_at', NEW.updated_at),
            'teller_write', COALESCE(NEW.created_at, CURRENT_TIMESTAMP));
END;

CREATE TRIGGER IF NOT EXISTS audit_identity_phone_number_insert
AFTER INSERT ON identity_phone_number
BEGIN
    INSERT INTO audit_log (table_name, record_id, action, new_data, changed_by, changed_at)
    VALUES ('identity_phone_number', CAST(NEW.identity_phone_number_id AS TEXT), 'INSERT',
            json_object('identity_phone_number_id', NEW.identity_phone_number_id, 'type', NEW.type, 'data', NEW.data, 'identity_id', NEW.identity_id, 'created_at', NEW.created_at, 'updated_at', NEW.updated_at),
            'teller_write', COALESCE(NEW.created_at, CURRENT_TIMESTAMP));
END;

CREATE TRIGGER IF NOT EXISTS audit_identity_address_data_insert
AFTER INSERT ON identity_address_data
BEGIN
    INSERT INTO audit_log (table_name, record_id, action, new_data, changed_by, changed_at)
    VALUES ('identity_address_data', CAST(NEW.identity_address_data_id AS TEXT), 'INSERT',
            json_object('identity_address_data_id', NEW.identity_address_data_id, 'street', NEW.street, 'city', NEW.city, 'region', NEW.region, 'country', NEW.country, 'postal_code', NEW.postal_code, 'created_at', NEW.created_at, 'updated_at', NEW.updated_at),
            'teller_write', COALESCE(NEW.created_at, CURRENT_TIMESTAMP));
END;

CREATE TRIGGER IF NOT EXISTS audit_identity_address_insert
AFTER INSERT ON identity_address
BEGIN
    INSERT INTO audit_log (table_name, record_id, action, new_data, changed_by, changed_at)
    VALUES ('identity_address', CAST(NEW.identity_address_id AS TEXT), 'INSERT',
            json_object('identity_address_id', NEW.identity_address_id, 'primary_address', NEW.primary_address, 'identity_address_data_id', NEW.identity_address_data_id, 'identity_id', NEW.identity_id, 'created_at', NEW.created_at, 'updated_at', NEW.updated_at),
            'teller_write', COALESCE(NEW.created_at, CURRENT_TIMESTAMP));
END;

CREATE TRIGGER IF NOT EXISTS audit_account_identities_insert
AFTER INSERT ON account_identities
BEGIN
    INSERT INTO audit_log (table_name, record_id, action, new_data, changed_by, changed_at)
    VALUES ('account_identities', CAST(NEW.account_identities_id AS TEXT), 'INSERT',
            json_object('account_identities_id', NEW.account_identities_id, 'account_id', NEW.account_id, 'identity_id', NEW.identity_id, 'created_at', NEW.created_at, 'updated_at', NEW.updated_at),
            'teller_write', COALESCE(NEW.created_at, CURRENT_TIMESTAMP));
END;

CREATE TRIGGER IF NOT EXISTS audit_account_balances_links_insert
AFTER INSERT ON account_balances_links
BEGIN
    INSERT INTO audit_log (table_name, record_id, action, new_data, changed_by, changed_at)
    VALUES ('account_balances_links', CAST(NEW.account_balances_links_id AS TEXT), 'INSERT',
            json_object('account_balances_links_id', NEW.account_balances_links_id, 'self_link', NEW.self_link, 'account_link', NEW.account_link, 'created_at', NEW.created_at, 'updated_at', NEW.updated_at),
            'teller_write', COALESCE(NEW.created_at, CURRENT_TIMESTAMP));
END;

CREATE TRIGGER IF NOT EXISTS audit_account_balances_insert
AFTER INSERT ON account_balances
BEGIN
    INSERT INTO audit_log (table_name, record_id, action, new_data, changed_by, changed_at)
    VALUES ('account_balances', CAST(NEW.account_balances_id AS TEXT), 'INSERT',
            json_object('account_balances_id', NEW.account_balances_id, 'account_id', NEW.account_id, 'ledger', NEW.ledger, 'available', NEW.available, 'account_balances_links_id', NEW.account_balances_links_id, 'created_at', NEW.created_at, 'updated_at', NEW.updated_at),
            'teller_write', COALESCE(NEW.created_at, CURRENT_TIMESTAMP));
END;

CREATE TRIGGER IF NOT EXISTS audit_transaction_type_insert
AFTER INSERT ON transaction_type
BEGIN
    INSERT INTO audit_log (table_name, record_id, action, new_data, changed_by, changed_at)
    VALUES ('transaction_type', CAST(NEW.transaction_type_id AS TEXT), 'INSERT',
            json_object('transaction_type_id', NEW.transaction_type_id, 'code', NEW.code, 'created_at', NEW.created_at, 'updated_at', NEW.updated_at),
            'teller_write', COALESCE(NEW.created_at, CURRENT_TIMESTAMP));
END;

CREATE TRIGGER IF NOT EXISTS audit_transaction_details_counterparty_insert
AFTER INSERT ON transaction_details_counterparty
BEGIN
    INSERT INTO audit_log (table_name, record_id, action, new_data, changed_by, changed_at)
    VALUES ('transaction_details_counterparty', CAST(NEW.transaction_details_counterparty_id AS TEXT), 'INSERT',
            json_object('transaction_details_counterparty_id', NEW.transaction_details_counterparty_id, 'name', NEW.name, 'type', NEW.type, 'created_at', NEW.created_at, 'updated_at', NEW.updated_at),
            'teller_write', COALESCE(NEW.created_at, CURRENT_TIMESTAMP));
END;

CREATE TRIGGER IF NOT EXISTS audit_transaction_details_insert
AFTER INSERT ON transaction_details
BEGIN
    INSERT INTO audit_log (table_name, record_id, action, new_data, changed_by, changed_at)
    VALUES ('transaction_details', CAST(NEW.transaction_details_id AS TEXT), 'INSERT',
            json_object('transaction_details_id', NEW.transaction_details_id, 'processing_status', NEW.processing_status, 'category', NEW.category, 'transaction_details_counterparty_id', NEW.transaction_details_counterparty_id, 'created_at', NEW.created_at, 'updated_at', NEW.updated_at),
            'teller_write', COALESCE(NEW.created_at, CURRENT_TIMESTAMP));
END;

CREATE TRIGGER IF NOT EXISTS audit_transaction_links_insert
AFTER INSERT ON transaction_links
BEGIN
    INSERT INTO audit_log (table_name, record_id, action, new_data, changed_by, changed_at)
    VALUES ('transaction_links', CAST(NEW.transaction_links_id AS TEXT), 'INSERT',
            json_object('transaction_links_id', NEW.transaction_links_id, 'self_link', NEW.self_link, 'account', NEW.account, 'created_at', NEW.created_at, 'updated_at', NEW.updated_at),
            'teller_write', COALESCE(NEW.created_at, CURRENT_TIMESTAMP));
END;

CREATE TRIGGER IF NOT EXISTS audit_transaction_insert
AFTER INSERT ON "transaction"
BEGIN
    INSERT INTO audit_log (table_name, record_id, action, new_data, changed_by, changed_at)
    VALUES ('transaction', NEW.transaction_id, 'INSERT',
            json_object('transaction_id', NEW.transaction_id, 'account_id', NEW.account_id, 'amount', NEW.amount, 'date', NEW.date, 'description', NEW.description, 'transaction_details_id', NEW.transaction_details_id, 'status', NEW.status, 'transaction_links_id', NEW.transaction_links_id, 'running_balance', NEW.running_balance, 'transaction_type_id', NEW.transaction_type_id, 'created_at', NEW.created_at, 'updated_at', NEW.updated_at),
            'teller_write', COALESCE(NEW.created_at, CURRENT_TIMESTAMP));
END;

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
