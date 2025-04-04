from minimal_postgres_client import MinimalPostgresClient
import os
from dotenv import load_dotenv
from contextlib import contextmanager
load_dotenv()

class TellerDBClient(MinimalPostgresClient):
    def __new__(cls):
        return super().__new__(cls, cls._get_db_connection_string(), "teller")

    @staticmethod
    def _get_db_config():
        return {    "user": os.environ.get("TELLER_POSTGRES_USER"),
                    "password": os.environ.get("TELLER_POSTGRES_PASSWORD"),
                    "host": os.environ.get("TELLER_POSTGRES_HOST"),
                    "port": os.environ.get("TELLER_POSTGRES_PORT"),
                    "dbname": os.environ.get("TELLER_POSTGRES_DB")
                }

    @classmethod
    def _get_db_connection_string(cls):
        config = cls._get_db_config()
        return f"host={config['host']} port={config['port']} dbname={config['dbname']} user={config['user']} password={config['password']}"
        
    @contextmanager
    def with_transaction(self):
        with self._get_connection() as conn:
            yield
