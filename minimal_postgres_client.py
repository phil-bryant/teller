import psycopg as _db
from typing import Dict, List, Any, Optional, Union
from textwrap import dedent
from collections import defaultdict

class MinimalPostgresClient:
    _instance = None

    def __new__(cls, connection_string: str, schema: str):   ## Singleton pattern
        if cls._instance is None:
            cls._instance = super().__new__(cls)
            cls._instance._connection = None
            cls._instance._connection_string = connection_string
            cls._instance._schema = schema                          ## "Minimal" = single-schema (for now)
            cls._instance._table_constraints_cache = {}
        return cls._instance

    def connect(self):
        return _db.connect(self._connection_string)

    def _get_connection(self): 
        if not self._connection: self._connection = self.connect()
        return self._connection

    def execute(self, sql: str) -> List[Dict[str, Any]]:
        connection = self._get_connection()
        results = []
        with connection.cursor(row_factory=_db.rows.dict_row) as cursor:
            print("\nDEBUG: About to execute sql:\n" + sql)
            cursor.execute(sql)
            if cursor.description: results = cursor.fetchall()
        return results

    def constraint_columns(self, table: str) -> str:
        constraints = self._get_table_constraints(table)
        cols = [col for col, types in constraints.items() if 'primary_key' in types or 'unique' in types]
        return ", ".join(cols)

    def commit(self) -> None:
        connection = self._get_connection()
        connection.commit()

    def upsert(self, table: str, data: Dict[str, Any]) -> Optional[Dict[str, Any]]:
        constraints = self._get_table_constraints(table)
        pk_cols = (col for col, types in constraints.items() if 'primary_key' in types and col in data and data[col] != "NULL")
        unique_cols = (col for col, types in constraints.items() if 'unique' in types and col in data and data[col] != "NULL")
        fallback_pk = (col for col, types in constraints.items() if 'primary_key' in types)
        conflict_cols = next(pk_cols, next(unique_cols, next(fallback_pk, None)))
        query = f"INSERT INTO {self._schema}.{table} ({', '.join(data.keys())}) VALUES ({', '.join(data.values())})"
        if conflict_cols:
            updates = [f"{c} = EXCLUDED.{c}" for c in data if data[c] and c != conflict_cols]
            query += f" ON CONFLICT ({conflict_cols}) DO {('UPDATE SET ' + ', '.join(updates)) if updates else 'NOTHING'}"
        query += " RETURNING *"
        return self.execute(dedent(query))

    def _get_table_constraints(self, table_name: str) -> dict:
        if table_name not in self._table_constraints_cache:
            constraints_data = self.execute(f"SELECT * FROM {self._schema}.table_constraints('{self._schema}', '{table_name}')")
            constraints = defaultdict(list)
            for row in constraints_data: constraints[row["column_name"]].append(row["constraint_type"])
            self._table_constraints_cache[table_name] = dict(constraints)
        return self._table_constraints_cache[table_name]

    def is_primary_key(self, table_name: str, field_name: str) -> bool:
        constraints = self._get_table_constraints(table_name)
        return field_name in constraints and 'primary_key' in constraints[field_name]

    def has_foreign_keys(self, table_name: str) -> bool:
        constraints = self._get_table_constraints(table_name)
        return any('foreign_key' in types for types in constraints.values())
