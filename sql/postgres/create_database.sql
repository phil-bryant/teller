SELECT format(
    'CREATE DATABASE %I WITH OWNER = postgres ENCODING = %L LC_COLLATE = %L LC_CTYPE = %L TEMPLATE = template0',
    :'db_name', 'UTF8', 'en_US.UTF-8', 'en_US.UTF-8'
)
WHERE NOT EXISTS (SELECT 1 FROM pg_database WHERE datname = :'db_name')
\gexec
