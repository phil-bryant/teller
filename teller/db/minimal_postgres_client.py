import psycopg as _db
from typing import Dict, List, Any, Optional, Union, ContextManager
from textwrap import dedent
from collections import defaultdict
from contextlib import contextmanager
import inspect

class MinimalPostgresClient:
    _instance = None

    def __new__(cls, connection_string: str):   ## Singleton pattern
        if cls._instance is None:
            cls._instance = super().__new__(cls)
            cls._instance._connection = None
            cls._instance._connection_string = connection_string
            cls._instance._column_information_cache = {}
            cls._instance._current_transaction_frames = set()
        return cls._instance

    def _connect(self):
        return _db.connect(self._connection_string, autocommit=True)

    def _get_connection(self): 
        if not self._connection: self._connection = self._connect()
        return self._connection

    @contextmanager
    def transaction(self) -> ContextManager[None]:
        ## Usage:   with client.transaction():
        ##              client.upsert(...)
        connection = self._get_connection()
        with connection.transaction():
            yield

    def _execute(self, sql: str) -> List[Dict[str, Any]]:
        connection = self._get_connection()
        results = []
        cursor = connection.cursor(row_factory=_db.rows.dict_row)
        try:
            print("\nDEBUG: About to execute sql:\n" + sql)
            cursor.execute(sql)
            if cursor.description: results = cursor.fetchall()
        finally:
            cursor.close()
        return results
    
    def _get_column_information(self, schema: str, table_name: str) -> dict:
        cache_key = (schema, table_name)
        if cache_key not in self._column_information_cache:
            sql = f"SELECT * FROM teller.column_information WHERE table_schema = '{schema}' AND table_name = '{table_name}'"
            column_data = self._execute(sql)
            columns_info = {row['column_name']: dict(row) for row in column_data} 
            self._column_information_cache[cache_key] = columns_info
        return self._column_information_cache[cache_key]
    
    def has_table_column(self, schema: str, table_name: str, column_name: str) -> bool:
        columns_info = self._get_column_information(schema, table_name)
        return column_name in columns_info
    
    def is_primary_key(self, schema: str, table_name: str, column_name: str) -> bool:
        all_columns_info = self._get_column_information(schema, table_name)
        column_info = all_columns_info.get(column_name)
        return column_info is not None and column_info.get('primary_key_constraint') is not None
    
    def constrains(self, my_schema: str, my_table: str, other_schema: str, other_table: str) -> bool:
        answer = False
        other_column_info = self._get_column_information(other_schema, other_table)
        for column_name, column_info in other_column_info.items():
            if column_info.get('foreign_table_schema') == my_schema and column_info.get('foreign_table_name') == my_table:
                answer = True
                break
        return answer

    def upsert(self, schema: str, table: str, data: Dict[str, Any]) -> Optional[Dict[str, Any]]:
        ## Usage:   with client.transaction():
        ##              client.upsert(...)
        all_columns_info = self._get_column_information(schema, table)
        valid_conflict_cols = []
        conflict_cols = []
        for col in conflict_cols:
            pk_constraint = all_columns_info.get(col, {}).get('primary_key_constraint')
            unique_constraint = all_columns_info.get(col, {}).get('unique_constraint')
            if pk_constraint is not None or unique_constraint is not None:
                valid_conflict_cols.append(col)
        query = f"INSERT INTO {schema}.{table} ({', '.join(data.keys())}) VALUES ({', '.join(data.values())})"
        if valid_conflict_cols:
            conflict_cols_str = ', '.join(valid_conflict_cols)
            update_cols = [f"{c} = EXCLUDED.{c}" for c in data if data[c] and c not in valid_conflict_cols]
            query += f" ON CONFLICT ({conflict_cols_str}) DO {('UPDATE SET ' + ', '.join(update_cols)) if update_cols else 'NOTHING'}"
        query += " RETURNING *"
        results = self._execute(dedent(query))
        return results[0] if results else None
