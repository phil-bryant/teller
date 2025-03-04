from postgres_client import PostgresClient

class TellerDBClient(PostgresClient):
    def __new__(cls, schema: str = "teller"):
        return super().__new__(cls, schema)

    def connect(self, connection_string: str = None) -> bool:
        connection_string = connection_string or "host=localhost dbname=prod user=teller password=QkCV#KC*eA9BDRx"
        return super().connect(connection_string)

    def table_exists(self, table: str) -> bool:
        query = """
        SELECT EXISTS (
            SELECT FROM pg_tables
            WHERE schemaname = %(schema)s AND tablename = %(table)s
        )
        """
        rows = self.execute(query, {"schema": self._schema, "table": table})
        return bool(rows and rows[0]["exists"])

    def get_tables(self):
        query = """
        SELECT tablename FROM pg_tables
        WHERE schemaname = %(schema)s
        ORDER BY tablename
        """
        rows = self.execute(query, {"schema": self._schema})
        return [r["tablename"] for r in rows]

    def get_table_columns(self, table: str):
        query = """
        SELECT column_name, data_type, is_nullable, column_default
        FROM information_schema.columns
        WHERE table_schema = %(schema)s AND table_name = %(table)s
        ORDER BY ordinal_position
        """
        return self.execute(query, {"schema": self._schema, "table": table})

    def get_table_constraints(self, table: str):
        query = """
        SELECT con.conname as constraint_name, 
               con.contype as constraint_type,
               col.attname as column_name,
               CASE WHEN con.contype = 'f' THEN pg_get_constraintdef(con.oid) ELSE NULL END as definition
        FROM pg_constraint con
        JOIN pg_class tbl ON tbl.oid = con.conrelid
        JOIN pg_namespace ns ON ns.oid = tbl.relnamespace
        JOIN pg_attribute col ON col.attrelid = tbl.oid AND col.attnum = ANY(con.conkey)
        WHERE ns.nspname = %(schema)s AND tbl.relname = %(table)s
        """
        return self.execute(query, {"schema": self._schema, "table": table})