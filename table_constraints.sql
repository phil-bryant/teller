create or replace function table_constraints(schema_name text, table_name text)
returns table (
    schema_name text,
    table_name text,
    column_name text,
    constraint_type text,
    foreign_schema_name text,
    foreign_table_name text,
    num_columns int,
    column_num int,
    constraint_name text
) as $$
    select  *
    from    teller.all_table_constraints
    where   schema_name = $1 and table_name = $2
    order by schema_name, table_name, constraint_type, num_columns desc, column_num asc, column_name;
$$ language sql;

-- Example usage:
select * from table_constraints('teller', 'account');
