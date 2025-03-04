from minimal_postgres_client import MinimalPostgresClient
import os
from dotenv import load_dotenv

load_dotenv()

class TellerDBClient(MinimalPostgresClient):
    def __new__(cls, schema: str = "teller"):
        return super().__new__(cls, schema)

    @staticmethod
    def _get_db_config():
        return {    "user": os.environ.get("TELLER_POSTGRES_USER"),
                    "password": os.environ.get("TELLER_POSTGRES_PASSWORD"),
                    "host": os.environ.get("TELLER_POSTGRES_HOST", "localhost"),
                    "port": os.environ.get("TELLER_POSTGRES_PORT", "5432"),
                    "dbname": os.environ.get("TELLER_POSTGRES_DB", "prod")
                }

    @classmethod
    def _get_db_connection_string(cls):
        config = cls._get_db_config()
        return f"host={config['host']} port={config['port']} dbname={config['dbname']} user={config['user']} password={config['password']}"

    def connect(self, connection_string: str = None) -> bool:
        connection_string = connection_string or self._get_db_connection_string()
        return super().connect(connection_string)