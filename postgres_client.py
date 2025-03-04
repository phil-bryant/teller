import psycopg as db
from typing import Dict, List, Any, Optional

class PostgresClient:
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
        placeholders = ', '.join([f'%({k})s' for k in data])
        query = f"INSERT INTO {self._schema}.{table} ({columns}) VALUES ({placeholders}) RETURNING *"
        rows = self.execute(query, data)
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