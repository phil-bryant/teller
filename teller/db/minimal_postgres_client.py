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
        transaction_frame = inspect.currentframe().f_back
        self._current_transaction_frames.add(transaction_frame)
        try:
            with connection.transaction():
                yield
        finally:
            self._current_transaction_frames.discard(transaction_frame)

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
            sql = f"""
                SELECT
                    *
                FROM
                    teller.column_information
                WHERE
                    table_schema = '{schema}'
                    AND table_name = '{table_name}'
            """
            column_data = self._execute(dedent(sql))
            columns_info = {row['column_name']: dict(row) for row in column_data} 
            self._column_information_cache[cache_key] = columns_info
        return self._column_information_cache[cache_key]
    
    def has_table_column(self, schema: str, table_name: str, column_name: str) -> bool:
        print(f"DEBUG: Checking for column: {schema}.{table_name}.{column_name}")
        columns_info = self._get_column_information(schema, table_name)
        found = column_name in columns_info
        print(f"DEBUG: Column {column_name} found in cache: {found}")
        if not found: print(f"DEBUG: Available columns in cache for {schema}.{table_name}: {list(columns_info.keys())}")
        return found
    
    def is_primary_key(self, schema: str, table_name: str, column_name: str) -> bool:
        all_columns_info = self._get_column_information(schema, table_name)
        column_info = all_columns_info.get(column_name)
        return column_info is not None and column_info.get('primary_key_constraint') is not None

    def upsert(self, schema: str, table: str, data: Dict[str, Any]) -> Optional[Dict[str, Any]]:
        ## Usage:   with client.transaction():
        ##              client.upsert(...)
        caller_frame = inspect.currentframe().f_back
        current_frame = caller_frame
        in_transaction = False        
        while current_frame:
            if current_frame in self._current_transaction_frames:
                in_transaction = True
                break
            current_frame = current_frame.f_back
        all_columns_info = self._get_column_information(schema, table)
        
        pk_cols = []
        unique_cols = []
        for col_name, col_info in all_columns_info.items():
            if col_name in data and data[col_name] != "NULL":
                if col_info.get('primary_key_constraint') is not None: pk_cols.append(col_name)
                elif col_info.get('unique_constraint') is not None: unique_cols.append(col_name)
        
        print(f"DEBUG: Primary key columns found: {pk_cols}")
        print(f"DEBUG: Unique columns found: {unique_cols}")
        print(f"DEBUG: Data keys: {list(data.keys())}")
        
        # Check if any PK columns from schema are missing from data
        for col_name, col_info in all_columns_info.items():
            if col_info.get('primary_key_constraint') is not None and col_name not in data:
                print(f"DEBUG: Warning: Primary key column '{col_name}' exists in schema but not in data")

        conflict_cols = pk_cols if pk_cols else unique_cols
        print(f"DEBUG: Final conflict columns: {conflict_cols}")
        
        for col in conflict_cols:
            pk_constraint = all_columns_info.get(col, {}).get('primary_key_constraint')
            unique_constraint = all_columns_info.get(col, {}).get('unique_constraint')
            print(f"DEBUG: Validating conflict column '{col}': pk_constraint={pk_constraint}, unique_constraint={unique_constraint}")
        
        query = f"INSERT INTO {schema}.{table} ({', '.join(data.keys())}) VALUES ({', '.join(data.values())})"
        
        # Only add the ON CONFLICT clause if we have conflict columns
        if conflict_cols:
            print(f"DEBUG: Adding ON CONFLICT clause with columns: {conflict_cols}")
            conflict_cols_str = ', '.join(conflict_cols)
            update_cols = [f"{c} = EXCLUDED.{c}" for c in data if data[c] and c not in conflict_cols]
            query += f" ON CONFLICT ({conflict_cols_str}) DO {('UPDATE SET ' + ', '.join(update_cols)) if update_cols else 'NOTHING'}"
        else:
            print(f"DEBUG: No conflict columns found, using simple INSERT")
        
        query += " RETURNING *"
        results = self._execute(dedent(query))
        return results[0] if results else None
