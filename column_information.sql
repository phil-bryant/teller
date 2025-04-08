-- column_information.sql

CREATE OR REPLACE VIEW teller.column_information AS
SELECT *
FROM information_schema.columns
NATURAL LEFT JOIN teller.column_constraints
WHERE information_schema.columns.table_schema = 'teller';