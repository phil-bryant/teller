BEGIN;

-- #R001: Normalize mutable hierarchy text fields before constraint enforcement.
-- Normalize printable hierarchy values before enforcing constraints.
UPDATE classy.nys_snw_category
   SET level_1 = NULLIF(BTRIM(REGEXP_REPLACE(level_1, '[[:cntrl:]]', '', 'g')), ''),
       level_1_name = NULLIF(BTRIM(REGEXP_REPLACE(level_1_name, '[[:cntrl:]]', '', 'g')), ''),
       level_2 = NULLIF(BTRIM(REGEXP_REPLACE(level_2, '[[:cntrl:]]', '', 'g')), ''),
       level_2_name = NULLIF(BTRIM(REGEXP_REPLACE(level_2_name, '[[:cntrl:]]', '', 'g')), ''),
       level_3 = NULLIF(BTRIM(REGEXP_REPLACE(level_3, '[[:cntrl:]]', '', 'g')), ''),
       level_4 = NULLIF(BTRIM(REGEXP_REPLACE(level_4, '[[:cntrl:]]', '', 'g')), ''),
       categorization = NULLIF(BTRIM(REGEXP_REPLACE(categorization, '[[:cntrl:]]', '', 'g')), ''),
       applicability = NULLIF(BTRIM(REGEXP_REPLACE(applicability, '[[:cntrl:]]', '', 'g')), '');

DO $$
DECLARE
    empty_rows BIGINT;
BEGIN
    -- #R005: Refuse constraint installation while empty hierarchy rows remain.
    SELECT COUNT(*)
      INTO empty_rows
      FROM classy.nys_snw_category
     WHERE COALESCE(
               NULLIF(BTRIM(level_1), ''),
               NULLIF(BTRIM(level_1_name), ''),
               NULLIF(BTRIM(level_2), ''),
               NULLIF(BTRIM(level_2_name), ''),
               NULLIF(BTRIM(level_3), ''),
               NULLIF(BTRIM(level_4), ''),
               NULLIF(BTRIM(categorization), ''),
               NULLIF(BTRIM(applicability), '')
           ) IS NULL;
    IF empty_rows > 0 THEN
        RAISE EXCEPTION
            'Cannot enforce nys_snw_category constraints: % empty hierarchy rows remain',
            empty_rows;
    END IF;
END $$;

ALTER TABLE classy.nys_snw_category
    -- #R010: Recreate and validate hierarchy integrity constraints.
    DROP CONSTRAINT IF EXISTS nys_snw_category_non_empty_hierarchy_chk,
    DROP CONSTRAINT IF EXISTS nys_snw_category_no_control_chars_chk;

ALTER TABLE classy.nys_snw_category
    ADD CONSTRAINT nys_snw_category_non_empty_hierarchy_chk CHECK (
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
    ) NOT VALID,
    ADD CONSTRAINT nys_snw_category_no_control_chars_chk CHECK (
        (level_1 IS NULL OR level_1 !~ '[[:cntrl:]]')
        AND (level_1_name IS NULL OR level_1_name !~ '[[:cntrl:]]')
        AND (level_2 IS NULL OR level_2 !~ '[[:cntrl:]]')
        AND (level_2_name IS NULL OR level_2_name !~ '[[:cntrl:]]')
        AND (level_3 IS NULL OR level_3 !~ '[[:cntrl:]]')
        AND (level_4 IS NULL OR level_4 !~ '[[:cntrl:]]')
        AND (categorization IS NULL OR categorization !~ '[[:cntrl:]]')
        AND (applicability IS NULL OR applicability !~ '[[:cntrl:]]')
    ) NOT VALID;

ALTER TABLE classy.nys_snw_category
    VALIDATE CONSTRAINT nys_snw_category_non_empty_hierarchy_chk;

ALTER TABLE classy.nys_snw_category
    VALIDATE CONSTRAINT nys_snw_category_no_control_chars_chk;

COMMIT;
