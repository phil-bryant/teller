import psycopg as db
from typing import Dict, List, Any, Optional, Union
import traceback
from pprint import pprint

class MinimalPostgresClient:
    _instance = None

    def __new__(cls, schema: str = "public"):
        if cls._instance is None:
            cls._instance = super().__new__(cls)
            cls._instance._conn = None
            cls._instance._schema = schema
        return cls._instance

    def connect(self, connection_string: str) -> bool:
        self._conn = db.connect(connection_string)
        return bool(self._conn)

    def execute(self, query: str, params: Optional[Dict[str, Any]] = None) -> List[Dict[str, Any]]:
        result = []
        if self._conn:
            with self._conn.cursor(row_factory=db.rows.dict_row) as cursor:
                cursor.execute(query, params or {})
                if cursor.description: result = cursor.fetchall()
        return result

    def insert(self, table: str, data: Dict[str, Any]) -> Optional[Dict[str, Any]]:
        columns = ', '.join(data.keys())
        values = []
        for k, val in data.items():
            if val is None or val == '':
                values.append("NULL")
            else:
                val_str = str(val).replace("'", "''")
                values.append(f"'{val_str}'")        
        value_str = ', '.join(values)
        query = f"INSERT INTO {self._schema}.{table} ({columns}) VALUES ({value_str}) RETURNING *"
        print(f"EXECUTING SQL: {query}")
        rows = self.execute(query, None)
        self.commit()
        print(f"INSERT RESULT: {rows}")
        return rows[0] if rows else None

    def update(self, table: str, data: Dict[str, Any], pk_column: str) -> Optional[Dict[str, Any]]:
        set_clause = ', '.join([f'{k} = %({k})s' for k in data if k != pk_column])
        query = f"UPDATE {self._schema}.{table} SET {set_clause} WHERE {pk_column} = %({pk_column})s RETURNING *"
        rows = self.execute(query, data)
        return rows[0] if rows else None

    def select(self, table: str, conditions: Dict[str, Any] = None) -> List[Dict[str, Any]]:
        query = f"SELECT * FROM {self._schema}.{table}"
        if conditions:
            clauses = ' AND '.join([f"{col} = %({col})s" for col in conditions])
            query += f" WHERE {clauses}"
        return self.execute(query, conditions)

    def delete(self, table: str, conditions: Dict[str, Any]) -> bool:
        clauses = ' AND '.join([f"{col} = %({col})s" for col in conditions])
        query = f"DELETE FROM {self._schema}.{table} WHERE {clauses}"
        self.execute(query, conditions)
        self.commit()
        return True

    def commit(self) -> None:
        self._conn.commit()

    def rollback(self) -> None:
        self._conn.rollback()
        
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