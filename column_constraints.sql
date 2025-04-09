-- column_constraints.sql

CREATE OR REPLACE VIEW teller.column_constraints (
    table_schema,
    table_name,
    column_name,
    num_constraint_cols,
    constraint_col_num,
    check_constraint,
    not_null_constraint,
    unique_constraint,
    primary_key_constraint,
    foreign_key_constraint,
    foreign_table_schema,
    foreign_table_name,
    is_deferrable,
    initially_deferred
) AS WITH distinct_cols AS (
    -- Get the unique identifiers for rows and aggregate deferrability/FK info
    SELECT
        ac.table_schema,
        ac.table_name,
        ac.column_name,
        -- Aggregate FK details, only considering rows where constraint_type is 'foreign_key'
        MAX(CASE WHEN ac.constraint_type = 'foreign_key' THEN ac.foreign_table_schema ELSE NULL END) AS foreign_table_schema,
        MAX(CASE WHEN ac.constraint_type = 'foreign_key' THEN ac.foreign_table_name ELSE NULL END) AS foreign_table_name,
        -- Aggregate deferrability
        MAX(ac.is_deferrable::text) AS is_deferrable,
        MAX(ac.initially_deferred::text) AS initially_deferred,
        MAX(ac.num_columns) AS num_constraint_cols,
        MAX(ac.column_num) AS constraint_col_num
    FROM teller.table_constraints ac
    WHERE ac.table_schema = 'teller'
    GROUP BY
        ac.table_schema,
        ac.table_name,
        ac.column_name
)
SELECT
    dc.table_schema,
    dc.table_name,
    dc.column_name,
    dc.num_constraint_cols,
    dc.constraint_col_num,
    ct.check_constraint,
    ct.not_null_constraint,
    ct.unique_constraint,
    ct.primary_key_constraint,
    ct.foreign_key_constraint,
    -- Aggregated FK info from distinct_cols CTE (before defer cols)
    dc.foreign_table_schema,
    dc.foreign_table_name,
    -- Aggregated deferrability info from distinct_cols CTE
    dc.is_deferrable,
    dc.initially_deferred
FROM distinct_cols dc
LEFT JOIN crosstab(
    $$ -- Inner query: Provides row_id, category, and aggregated constraint_name
       -- CTE must be defined INSIDE the dollar-quoted string
       WITH aggregated_constraints AS (
           SELECT
               agg_ac.table_schema,
               agg_ac.table_name,
               agg_ac.column_name,
               agg_ac.constraint_type,
               string_agg(agg_ac.constraint_name, ', ') AS constraint_names -- Aggregate names if multiple
           FROM teller.table_constraints agg_ac
           WHERE agg_ac.table_schema = 'teller'
           GROUP BY
               agg_ac.table_schema,
               agg_ac.table_name,
               agg_ac.column_name,
               agg_ac.constraint_type
       )
       SELECT
           (agg_ac.table_schema || '.' || agg_ac.table_name || '.' || agg_ac.column_name) as schema_table_column_name, -- Unique ID for grouping rows
           agg_ac.constraint_type,
           agg_ac.constraint_names -- Use the aggregated names
       FROM aggregated_constraints agg_ac
       ORDER BY 1, 2 -- IMPORTANT: Must order by row_id, then category
    $$,
    $$ -- Second query: Dynamically provides the distinct list of categories (column headers)
       SELECT DISTINCT cat_ac.constraint_type
       FROM teller.table_constraints cat_ac
       WHERE cat_ac.table_schema = 'teller'
       ORDER BY 1 -- Order is important for matching crosstab output definition
    $$
) AS ct (
    -- Define the output structure explicitly - THIS IS STILL REQUIRED by crosstab
    schema_table_column_name TEXT,
    -- The order MUST match the ORDER BY in the second query argument
    check_constraint TEXT,          -- 'check' comes first alphabetically
    foreign_key_constraint TEXT,    -- 'foreign_key' second
    not_null_constraint TEXT,       -- 'not_null' third
    primary_key_constraint TEXT,    -- 'primary_key' fourth
    unique_constraint TEXT          -- 'unique' fifth
)
-- Join the pivoted data back to the distinct columns using the schema_table_column_name
ON (dc.table_schema || '.' || dc.table_name || '.' || dc.column_name) = ct.schema_table_column_name; 