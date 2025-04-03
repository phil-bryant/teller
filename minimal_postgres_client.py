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
        constraint_query = dedent(f"""
            SELECT constraint_type, column_name
            FROM table_constraints('{self._schema}', '{table}')
            WHERE constraint_type IN ('primary_key', 'unique')
            ORDER BY constraint_type""")
        constraints = self.execute(constraint_query)
        conflict_cols = next((row["column_name"] for row in constraints 
                            if row["column_name"] in data and data[row["column_name"]] != "NULL"), None)
        if not conflict_cols and (all_cols := self.constraint_columns(table)): 
            conflict_cols = all_cols.split(',')[0].strip()
        query = f"INSERT INTO {self._schema}.{table} ({', '.join(data.keys())}) VALUES ({', '.join(data.values())})"
        if conflict_cols:
            updates = [f"{c} = EXCLUDED.{c}" for c in data if data[c] and c not in conflict_cols.split(',')]
            query += f" ON CONFLICT ({conflict_cols}) DO {('UPDATE SET ' + ', '.join(updates)) if updates else 'NOTHING'}"
        query += " RETURNING *"
        rows = self.execute(dedent(query))
        self.commit()
        return rows
    