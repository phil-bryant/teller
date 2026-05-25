CREATE TABLE IF NOT EXISTS teller.nys_snw_category (
    nys_snw_category_id BIGSERIAL PRIMARY KEY,
    level_1 TEXT,
    level_1_name TEXT,
    level_2 TEXT,
    level_2_name TEXT,
    level_3 TEXT,
    level_4 TEXT,
    categorization TEXT,
    applicability TEXT,
    is_seed BOOLEAN NOT NULL DEFAULT FALSE,
    CONSTRAINT nys_snw_category_text_length_chk CHECK (
        (level_1 IS NULL OR CHAR_LENGTH(level_1) <= 120)
        AND (level_1_name IS NULL OR CHAR_LENGTH(level_1_name) <= 120)
        AND (level_2 IS NULL OR CHAR_LENGTH(level_2) <= 120)
        AND (level_2_name IS NULL OR CHAR_LENGTH(level_2_name) <= 120)
        AND (level_3 IS NULL OR CHAR_LENGTH(level_3) <= 120)
        AND (level_4 IS NULL OR CHAR_LENGTH(level_4) <= 120)
        AND (categorization IS NULL OR CHAR_LENGTH(categorization) <= 120)
        AND (applicability IS NULL OR CHAR_LENGTH(applicability) <= 120)
    ),
    CONSTRAINT nys_snw_category_non_empty_hierarchy_chk CHECK (
        COALESCE(
            NULLIF(BTRIM(level_1), ''),
            NULLIF(BTRIM(level_1_name), ''),
            NULLIF(BTRIM(level_2), ''),
            NULLIF(BTRIM(level_2_name), ''),
            NULLIF(BTRIM(level_3), ''),
            NULLIF(BTRIM(level_4), ''),
            NULLIF(BTRIM(categorization), ''),
            NULLIF(BTRIM(applicability), '')
        ) IS NOT NULL
    ),
    CONSTRAINT nys_snw_category_no_control_chars_chk CHECK (
        (level_1 IS NULL OR level_1 !~ '[[:cntrl:]]')
        AND (level_1_name IS NULL OR level_1_name !~ '[[:cntrl:]]')
        AND (level_2 IS NULL OR level_2 !~ '[[:cntrl:]]')
        AND (level_2_name IS NULL OR level_2_name !~ '[[:cntrl:]]')
        AND (level_3 IS NULL OR level_3 !~ '[[:cntrl:]]')
        AND (level_4 IS NULL OR level_4 !~ '[[:cntrl:]]')
        AND (categorization IS NULL OR categorization !~ '[[:cntrl:]]')
        AND (applicability IS NULL OR applicability !~ '[[:cntrl:]]')
    ),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);
COMMENT ON TABLE teller.nys_snw_category IS 'NYS Statement of Net Worth category mapping table.';
COMMENT ON COLUMN teller.nys_snw_category.categorization IS 'NYS SNW category label.';
COMMENT ON COLUMN teller.nys_snw_category.applicability IS 'Applicability guidance from the source document.';
COMMENT ON COLUMN teller.nys_snw_category.is_seed IS 'True for canonical taxonomy rows loaded from seed SQL.';
CREATE UNIQUE INDEX IF NOT EXISTS nys_snw_category_unique_hierarchy_idx ON teller.nys_snw_category (
    level_1, level_1_name, level_2, level_2_name, level_3, COALESCE(level_4, ''), COALESCE(categorization, ''),
    COALESCE(applicability, '')
);

INSERT INTO teller.nys_snw_category (level_1, level_1_name, level_2, level_2_name, level_3, level_4, categorization, applicability)
SELECT * FROM (VALUES
    ('II.', 'EXPENSES:', '(a)', 'Housing: Monthly', '1.', NULL, 'Mortgage/Co-op Loan', 'N/A'),
    ('II.', 'EXPENSES:', '(a)', 'Housing: Monthly', '2.', NULL, 'Home Equity Line of Credit/Second Mortgage', 'N/A'),
    ('II.', 'EXPENSES:', '(a)', 'Housing: Monthly', '3.', NULL, 'Real Estate Taxes', 'N/A'),
    ('II.', 'EXPENSES:', '(a)', 'Housing: Monthly', '4.', NULL, 'Homeowners/Renter’s Insurance', 'N/A'),
    ('II.', 'EXPENSES:', '(a)', 'Housing: Monthly', '5.', NULL, 'Homeowner’s Association/Maintenance charges/Condominium Charges', 'N/A'),
    ('II.', 'EXPENSES:', '(a)', 'Housing: Monthly', '6.', NULL, 'Rent', NULL),
    ('II.', 'EXPENSES:', '(a)', 'Housing: Monthly', '7.', NULL, 'Other', 'N/A'),
    ('II.', 'EXPENSES:', '(b)', 'Utilities:  Monthly', '1.', NULL, 'Fuel Oil/Gas', 'N/A'),
    ('II.', 'EXPENSES:', '(b)', 'Utilities:  Monthly', '2.', NULL, 'Electric', 'N/A'),
    ('II.', 'EXPENSES:', '(b)', 'Utilities:  Monthly', '3.', NULL, 'Telephone (land line)', 'N/A'),
    ('II.', 'EXPENSES:', '(b)', 'Utilities:  Monthly', '4.', NULL, 'Mobile Phone', NULL),
    ('II.', 'EXPENSES:', '(b)', 'Utilities:  Monthly', '5.', NULL, 'Cable/Satellite TV', NULL),
    ('II.', 'EXPENSES:', '(b)', 'Utilities:  Monthly', '6.', NULL, 'Internet', NULL),
    ('II.', 'EXPENSES:', '(b)', 'Utilities:  Monthly', '7.', NULL, 'Alarm', 'N/A'),
    ('II.', 'EXPENSES:', '(b)', 'Utilities:  Monthly', '8.', NULL, 'Water', 'N/A'),
    ('II.', 'EXPENSES:', '(b)', 'Utilities:  Monthly', '9.', NULL, 'Other', NULL),
    ('II.', 'EXPENSES:', '(c)', 'Food: Monthly', '1.', NULL, 'Groceries', NULL),
    ('II.', 'EXPENSES:', '(c)', 'Food: Monthly', '2.', NULL, 'Dining Out/Take Out', NULL),
    ('II.', 'EXPENSES:', '(c)', 'Food: Monthly', '3.', NULL, 'Other', NULL),
    ('II.', 'EXPENSES:', '(d)', 'Clothing:  Monthly', '1.', NULL, 'Yourself', NULL),
    ('II.', 'EXPENSES:', '(d)', 'Clothing:  Monthly', '2.', NULL, 'Child(ren)', 'N/A'),
    ('II.', 'EXPENSES:', '(d)', 'Clothing:  Monthly', '3.', NULL, 'Dry Cleaning', NULL),
    ('II.', 'EXPENSES:', '(d)', 'Clothing:  Monthly', '4.', NULL, 'Other', NULL),
    ('II.', 'EXPENSES:', '(e)', 'Insurance: Monthly', '1.', NULL, 'Life', 'N/A'),
    ('II.', 'EXPENSES:', '(e)', 'Insurance: Monthly', '2.', NULL, 'Fire, theft and liability and personal articles policy', 'N/A'),
    ('II.', 'EXPENSES:', '(e)', 'Insurance: Monthly', '3.', NULL, 'Automotive', 'N/A'),
    ('II.', 'EXPENSES:', '(e)', 'Insurance: Monthly', '4.', NULL, 'Umbrella Policy', 'N/A'),
    ('II.', 'EXPENSES:', '(e)', 'Insurance: Monthly', '5.', NULL, 'Medical Plan', NULL),
    ('II.', 'EXPENSES:', '(e)', 'Insurance: Monthly', '5.', 'A.', 'Medical Plan for yourself', NULL),
    ('II.', 'EXPENSES:', '(e)', 'Insurance: Monthly', '5.', 'B.', 'Medical Plan for children', 'N/A'),
    ('II.', 'EXPENSES:', '(e)', 'Insurance: Monthly', '6.', NULL, 'Dental Plan', 'N/A'),
    ('II.', 'EXPENSES:', '(e)', 'Insurance: Monthly', '7.', NULL, 'Optical Plan', 'N/A'),
    ('II.', 'EXPENSES:', '(e)', 'Insurance: Monthly', '8.', NULL, 'Disability', 'N/A'),
    ('II.', 'EXPENSES:', '(e)', 'Insurance: Monthly', '9.', NULL, 'Worker’s Compensation', 'N/A'),
    ('II.', 'EXPENSES:', '(e)', 'Insurance: Monthly', '10.', NULL, 'Long Term Care Insurance', 'N/A'),
    ('II.', 'EXPENSES:', '(e)', 'Insurance: Monthly', '11.', NULL, 'Other', 'N/A'),
    ('II.', 'EXPENSES:', '(f)', 'Unreimbursed Medical:  Monthly', '1.', NULL, 'Medical', NULL),
    ('II.', 'EXPENSES:', '(f)', 'Unreimbursed Medical:  Monthly', '2.', NULL, 'Dental', NULL),
    ('II.', 'EXPENSES:', '(f)', 'Unreimbursed Medical:  Monthly', '3.', NULL, 'Optical', NULL),
    ('II.', 'EXPENSES:', '(f)', 'Unreimbursed Medical:  Monthly', '4.', NULL, 'Pharmaceutical', NULL),
    ('II.', 'EXPENSES:', '(f)', 'Unreimbursed Medical:  Monthly', '5.', NULL, 'Surgical, Nursing, Hospital', NULL),
    ('II.', 'EXPENSES:', '(f)', 'Unreimbursed Medical:  Monthly', '6.', NULL, 'Psychotherapy', NULL),
    ('II.', 'EXPENSES:', '(f)', 'Unreimbursed Medical:  Monthly', '7.', NULL, 'Other', 'N/A'),
    ('II.', 'EXPENSES:', '(g)', 'Household Maintenance:  Monthly', '1.', NULL, 'Repairs/Maintenance', 'N/A'),
    ('II.', 'EXPENSES:', '(g)', 'Household Maintenance:  Monthly', '2.', NULL, 'Gardening/landscaping', 'N/A'),
    ('II.', 'EXPENSES:', '(g)', 'Household Maintenance:  Monthly', '3.', NULL, 'Sanitation/carting', 'N/A'),
    ('II.', 'EXPENSES:', '(g)', 'Household Maintenance:  Monthly', '4.', NULL, 'Snow Removal', 'N/A'),
    ('II.', 'EXPENSES:', '(g)', 'Household Maintenance:  Monthly', '5.', NULL, 'Extermination', 'N/A'),
    ('II.', 'EXPENSES:', '(g)', 'Household Maintenance:  Monthly', '6.', NULL, 'Other', 'N/A'),
    ('II.', 'EXPENSES:', '(h)', 'Household Help:  Monthly', '1.', NULL, 'Domestic (housekeeper, etc.)', 'N/A'),
    ('II.', 'EXPENSES:', '(h)', 'Household Help:  Monthly', '2.', NULL, 'Nanny/Au Pair/Child Care', 'N/A'),
    ('II.', 'EXPENSES:', '(h)', 'Household Help:  Monthly', '3.', NULL, 'Babysitter', 'N/A'),
    ('II.', 'EXPENSES:', '(h)', 'Household Help:  Monthly', '4.', NULL, 'Other', 'N/A'),
    ('II.', 'EXPENSES:', '(i)', 'Automobile:  Monthly', '1.', NULL, 'Lease or Loan Payments (indicate lease term)', 'N/A'),
    ('II.', 'EXPENSES:', '(i)', 'Automobile:  Monthly', '2.', NULL, 'Gas and Oil', NULL),
    ('II.', 'EXPENSES:', '(i)', 'Automobile:  Monthly', '3.', NULL, 'Repairs', 'N/A'),
    ('II.', 'EXPENSES:', '(i)', 'Automobile:  Monthly', '4.', NULL, 'Car Wash', 'N/A'),
    ('II.', 'EXPENSES:', '(i)', 'Automobile:  Monthly', '5.', NULL, 'Parking and tolls', 'N/A'),
    ('II.', 'EXPENSES:', '(i)', 'Automobile:  Monthly', '6.', NULL, 'Other', NULL),
    ('II.', 'EXPENSES:', '(j)', 'Education Costs:  Monthly', '1.', NULL, 'Nursery and Pre-school', 'N/A'),
    ('II.', 'EXPENSES:', '(j)', 'Education Costs:  Monthly', '2.', NULL, 'Primary and Secondary', 'N/A'),
    ('II.', 'EXPENSES:', '(j)', 'Education Costs:  Monthly', '3.', NULL, 'College', 'N/A'),
    ('II.', 'EXPENSES:', '(j)', 'Education Costs:  Monthly', '4.', NULL, 'Post-Graduate', 'N/A'),
    ('II.', 'EXPENSES:', '(j)', 'Education Costs:  Monthly', '5.', NULL, 'Religious Instruction', 'N/A'),
    ('II.', 'EXPENSES:', '(j)', 'Education Costs:  Monthly', '6.', NULL, 'School Transportation', 'N/A'),
    ('II.', 'EXPENSES:', '(j)', 'Education Costs:  Monthly', '7.', NULL, 'School Supplies/Books', 'N/A'),
    ('II.', 'EXPENSES:', '(j)', 'Education Costs:  Monthly', '8.', NULL, 'School Lunches', 'N/A'),
    ('II.', 'EXPENSES:', '(j)', 'Education Costs:  Monthly', '9.', NULL, 'Tutoring', 'N/A'),
    ('II.', 'EXPENSES:', '(j)', 'Education Costs:  Monthly', '10.', NULL, 'School Events', 'N/A'),
    ('II.', 'EXPENSES:', '(j)', 'Education Costs:  Monthly', '11.', NULL, 'Child(ren)’s extra-curricular and educational enrichment activities (Dance, Music, Sports, etc.)', 'N/A'),
    ('II.', 'EXPENSES:', '(j)', 'Education Costs:  Monthly', '12.', NULL, 'Other', 'N/A'),
    ('II.', 'EXPENSES:', '(k)', 'Recreational:  Monthly', '1.', NULL, 'Vacations', 'N/A'),
    ('II.', 'EXPENSES:', '(k)', 'Recreational:  Monthly', '2.', NULL, 'Movies, Theatre, Ballet, Etc.', 'N/A'),
    ('II.', 'EXPENSES:', '(k)', 'Recreational:  Monthly', '3.', NULL, 'Music (Digital or Physical Media)', NULL),
    ('II.', 'EXPENSES:', '(k)', 'Recreational:  Monthly', '4.', NULL, 'Recreation Clubs and Memberships', 'N/A'),
    ('II.', 'EXPENSES:', '(k)', 'Recreational:  Monthly', '5.', NULL, 'Activities for yourself', 'N/A'),
    ('II.', 'EXPENSES:', '(k)', 'Recreational:  Monthly', '6.', NULL, 'Health Club', 'N/A'),
    ('II.', 'EXPENSES:', '(k)', 'Recreational:  Monthly', '7.', NULL, 'Summer Camp', 'N/A'),
    ('II.', 'EXPENSES:', '(k)', 'Recreational:  Monthly', '8.', NULL, 'Birthday party costs for your child(ren)', 'N/A'),
    ('II.', 'EXPENSES:', '(k)', 'Recreational:  Monthly', '9.', NULL, 'Other', 'N/A'),
    ('II.', 'EXPENSES:', '(l)', 'Income Taxes:  Monthly', '1.', NULL, 'Federal', 'N/A'),
    ('II.', 'EXPENSES:', '(l)', 'Income Taxes:  Monthly', '2.', NULL, 'State', 'N/A'),
    ('II.', 'EXPENSES:', '(l)', 'Income Taxes:  Monthly', '3.', NULL, 'City', 'N/A'),
    ('II.', 'EXPENSES:', '(l)', 'Income Taxes:  Monthly', '4.', NULL, 'Social Security and Medicare', 'N/A'),
    ('II.', 'EXPENSES:', '(l)', 'Income Taxes:  Monthly', '5.', NULL, 'Number of dependents claimed in prior tax year', '0.'),
    ('II.', 'EXPENSES:', '(l)', 'Income Taxes:  Monthly', '6.', NULL, 'List any refund received by you for prior tax year', NULL),
    ('II.', 'EXPENSES:', '(m)', 'Miscellaneous:  Monthly', '1.', NULL, 'Beauty parlor/Barber/Spa', NULL),
    ('II.', 'EXPENSES:', '(m)', 'Miscellaneous:  Monthly', '2.', NULL, 'Toiletries/Non-Prescription Drugs', NULL),
    ('II.', 'EXPENSES:', '(m)', 'Miscellaneous:  Monthly', '3.', NULL, 'Books, magazines, newspapers', NULL),
    ('II.', 'EXPENSES:', '(m)', 'Miscellaneous:  Monthly', '4.', NULL, 'Gifts to others', NULL),
    ('II.', 'EXPENSES:', '(m)', 'Miscellaneous:  Monthly', '5.', NULL, 'Charitable contributions', 'N/A'),
    ('II.', 'EXPENSES:', '(m)', 'Miscellaneous:  Monthly', '6.', NULL, 'Religious organizations dues', 'N/A'),
    ('II.', 'EXPENSES:', '(m)', 'Miscellaneous:  Monthly', '7.', NULL, 'Union and organization dues', 'N/A'),
    ('II.', 'EXPENSES:', '(m)', 'Miscellaneous:  Monthly', '8.', NULL, 'Commutation expenses', 'N/A'),
    ('II.', 'EXPENSES:', '(m)', 'Miscellaneous:  Monthly', '9.', NULL, 'Veterinarian/pet expenses', NULL),
    ('II.', 'EXPENSES:', '(m)', 'Miscellaneous:  Monthly', '10.', NULL, 'Child support payments (for Child(ren) of a prior marriage or relationship pursuant to court order or agreement)', 'N/A'),
    ('II.', 'EXPENSES:', '(m)', 'Miscellaneous:  Monthly', '11.', NULL, 'Alimony and maintenance payments (prior marriage pursuant to court order or agreement)', 'N/A'),
    ('II.', 'EXPENSES:', '(m)', 'Miscellaneous:  Monthly', '12.', NULL, 'Loan payments', 'N/A'),
    ('II.', 'EXPENSES:', '(m)', 'Miscellaneous:  Monthly', '13.', NULL, 'Unreimbursed business expenses', NULL),
    ('II.', 'EXPENSES:', '(m)', 'Miscellaneous:  Monthly', '14.', NULL, 'Safe Deposit Box rental fee', 'N/A'),
    ('II.', 'EXPENSES:', '(n)', 'Other:  Monthly', '1.', NULL, NULL, NULL),
    ('II.', 'EXPENSES:', '(n)', 'Other:  Monthly', '2.', NULL, NULL, NULL),
    ('II.', 'EXPENSES:', '(n)', 'Other:  Monthly', '3.', NULL, NULL, NULL),
    ('III.', 'GROSS INCOME INFORMATION:', '(a)', NULL, NULL, NULL, 'Gross (total) income - as should have been or should be reported in the most recent Federal income tax return.', NULL),
    ('III.', 'GROSS INCOME INFORMATION:', '(b)', 'To the extent not already included in gross income in (a) above:', '1.', NULL, 'Investment income, including interest and dividend income, reduced by sums expended in connection with such investment', NULL),
    ('III.', 'GROSS INCOME INFORMATION:', '(b)', 'To the extent not already included in gross income in (a) above:', '2.', NULL, 'Worker’s compensation (indicate percentage of amount due to lost wages)', 'N/A'),
    ('III.', 'GROSS INCOME INFORMATION:', '(b)', 'To the extent not already included in gross income in (a) above:', '3.', NULL, 'Disability benefits (indicate percentage of amount due to lost wages)', 'N/A'),
    ('III.', 'GROSS INCOME INFORMATION:', '(b)', 'To the extent not already included in gross income in (a) above:', '4.', NULL, 'Unemployment insurance benefits', 'N/A'),
    ('III.', 'GROSS INCOME INFORMATION:', '(b)', 'To the extent not already included in gross income in (a) above:', '5.', NULL, 'Social Security benefits', 'N/A'),
    ('III.', 'GROSS INCOME INFORMATION:', '(b)', 'To the extent not already included in gross income in (a) above:', '6.', NULL, 'Supplemental Security Income', 'N/A'),
    ('III.', 'GROSS INCOME INFORMATION:', '(b)', 'To the extent not already included in gross income in (a) above:', '7.', NULL, 'Public assistance', 'N/A'),
    ('III.', 'GROSS INCOME INFORMATION:', '(b)', 'To the extent not already included in gross income in (a) above:', '8.', NULL, 'Food stamps', 'N/A'),
    ('III.', 'GROSS INCOME INFORMATION:', '(b)', 'To the extent not already included in gross income in (a) above:', '9.', NULL, 'Veterans benefits', 'N/A'),
    ('III.', 'GROSS INCOME INFORMATION:', '(b)', 'To the extent not already included in gross income in (a) above:', '10.', NULL, 'Pensions and retirement benefits', 'N/A'),
    ('III.', 'GROSS INCOME INFORMATION:', '(b)', 'To the extent not already included in gross income in (a) above:', '11.', NULL, 'Fellowships and stipends', 'N/A'),
    ('III.', 'GROSS INCOME INFORMATION:', '(b)', 'To the extent not already included in gross income in (a) above:', '12.', NULL, 'Annuity payments', 'N/A')
) AS seed_rows(level_1, level_1_name, level_2, level_2_name, level_3, level_4, categorization, applicability)
WHERE NOT EXISTS (
    SELECT 1 FROM teller.nys_snw_category existing WHERE existing.is_seed = TRUE
);

UPDATE teller.nys_snw_category
   SET is_seed = TRUE
 WHERE nys_snw_category_id BETWEEN 1 AND 116
   AND is_seed = FALSE;

CREATE OR REPLACE FUNCTION teller.prevent_seed_category_mutation()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    IF TG_OP = 'UPDATE' THEN
        IF OLD.is_seed THEN
            RAISE EXCEPTION 'Seed category rows are immutable (id=%).', OLD.nys_snw_category_id
                USING ERRCODE = 'check_violation';
        END IF;
        IF NEW.is_seed <> OLD.is_seed THEN
            RAISE EXCEPTION 'Category seed provenance cannot be changed (id=%).', OLD.nys_snw_category_id
                USING ERRCODE = 'check_violation';
        END IF;
        RETURN NEW;
    ELSIF TG_OP = 'DELETE' THEN
        IF OLD.is_seed THEN
            RAISE EXCEPTION 'Seed category rows cannot be deleted (id=%).', OLD.nys_snw_category_id
                USING ERRCODE = 'check_violation';
        END IF;
        RETURN OLD;
    END IF;
    RETURN NULL;
END;
$$;

DROP TRIGGER IF EXISTS nys_snw_category_seed_guard_trg ON teller.nys_snw_category;
CREATE TRIGGER nys_snw_category_seed_guard_trg
BEFORE UPDATE OR DELETE ON teller.nys_snw_category
FOR EACH ROW
EXECUTE FUNCTION teller.prevent_seed_category_mutation();
