import psycopg as db
from typing import Dict, List, Any, Optional, Union
from textwrap import dedent

class MinimalPostgresClient:
    _instance = None

    def __new__(cls, schema: str = "public"):   ## Singleton pattern
        if cls._instance is None:
            cls._instance = super().__new__(cls)
            cls._instance._conn = None
            cls._instance._schema = schema          ## "Minimal" = single-schema (for now)
        return cls._instance

    def connect(self, connection_string: str) -> bool:
        self._conn = db.connect(connection_string)
        return bool(self._conn)

    def execute(self, sql: str) -> List[Dict[str, Any]]:
        results = []
        if self._conn:
            with self._conn.cursor(row_factory=db.rows.dict_row) as cursor:
                print("\nDEBUG: About to execute sql:\n" + sql)
                cursor.execute(sql)
                if cursor.description: results = cursor.fetchall()
        return results

    def constraint_columns(self, table: str) -> str:
        constraint_data = self.execute(dedent(f"""
                SELECT string_agg(column_name, ', ') as cols
                FROM table_constraints('{self._schema}', '{table}')
                WHERE constraint_type IN ('primary_key', 'unique')"""))
        return constraint_data[0]["cols"] if constraint_data and constraint_data[0]["cols"] else ""
    
    def commit(self) -> None:
        self._conn.commit()

    def upsert(self, table: str, data: Dict[str, Any]) -> Optional[Dict[str, Any]]:
        conflict_cols = self.constraint_columns(table)
        rows = self.execute(dedent(f"""
                INSERT INTO {self._schema}.{table} ({", ".join(data.keys())})
                VALUES ({", ".join(data.values())})
                ON CONFLICT ({conflict_cols}) DO UPDATE
                SET {", ".join([f"{col} = EXCLUDED.{col}" for col in data.keys() if data[col] and col not in conflict_cols])}
                RETURNING * """))
        self.commit()
        return rows
    