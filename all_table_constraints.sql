create or replace view teller.all_table_constraints as
select		s.nspname as schema_name, 
			t.relname as table_name, 
			a.attname as column_name, 
			case c.contype	when 'c'::"char" then 'check'::text
							when 'f'::"char" then 'foreign_key'::text
            				when 'p'::"char" then 'primary_key'::text
            				when 'u'::"char" then 'unique'::text
            				else null::text
        	end as constraint_type,
			fs.nspname as foreign_schema_name,
			ft.relname as foreign_table_name,
			array_length(c.conkey, 1) as num_columns,
			array_position(c.conkey, a.attnum) as column_num,
			c.conname as constraint_name,
			case when c.condeferrable then 'YES' else 'NO' end as is_deferrable,
			case when c.condeferred then 'YES' else 'NO' end as initially_deferred
from		pg_constraint c
			join pg_attribute a on a.attrelid = c.conrelid and a.attnum = any(c.conkey)
			join pg_class t on t.oid = c.conrelid
			join pg_namespace s on s.oid = c.connamespace
			left join pg_class ft on ft.oid = c.confrelid
			left join pg_namespace fs on fs.oid = ft.relnamespace
union all
select		nr.nspname as schema_name,
			r.relname as table_name,
			a.attname as column_name,
			'not_null'::text as constraint_type,
			null as foreign_schema_name,
			null as foreign_table_name,
			1 as num_columns,
			1 as column_num,
			(r.relname || '_' || a.attname || '_not_null') as constraint_name,
			'NO'::text as is_deferrable,
			'NO'::text as initially_deferred
from		pg_namespace nr
			join pg_class r on nr.oid = r.relnamespace
			join pg_attribute a on r.oid = a.attrelid
where		a.attnotnull and a.attnum > 0 and not a.attisdropped
			and r.relkind = any(array['r'::"char", 'p'::"char"])
			and nr.nspname = 'teller'
;