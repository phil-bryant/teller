from minimal_postgres_client import MinimalPostgresClient
import os
from dotenv import load_dotenv
from contextlib import contextmanager
import threading

load_dotenv()

class TellerDBClient(MinimalPostgresClient):
    _tx_state = threading.local()
    
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
    def smart_transaction(self):
        # Initialize transaction state trackers if needed
        if not hasattr(self._tx_state, 'in_transaction'):
            self._tx_state.in_transaction = False
            self._tx_state.defer_active = False
            self._tx_state.defer_requested = False
        
        # Detect if this is a nested call
        is_nested = self._tx_state.in_transaction
        self._tx_state.in_transaction = True
        
        # Get connection, start transaction
        connection = self._get_connection()
        tx = connection.transaction()
        
        # Handle constraints for top-level transactions
        if not is_nested and self._tx_state.defer_requested:
            self.execute("SET CONSTRAINTS ALL DEFERRED") 
            self._tx_state.defer_active = True
        
        try:
            yield self
            
            # Only commit at top level
            if not is_nested:
                if self._tx_state.defer_active:
                    self.execute("SET CONSTRAINTS ALL IMMEDIATE")
                connection.commit()
                self._tx_state.in_transaction = False
                self._tx_state.defer_active = False
        except Exception as e:
            if not is_nested:
                connection.rollback()
                self._tx_state.in_transaction = False
                self._tx_state.defer_active = False
            raise e
            
    def set_defer_constraints(self, defer=True):
        if not hasattr(self._tx_state, 'in_transaction'):
            self._tx_state.in_transaction = False
            self._tx_state.defer_active = False
        self._tx_state.defer_requested = defer