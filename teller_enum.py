from enum import Enum

class TellerEnum(Enum):
    """Base class for Teller Enums to provide shared db_value functionality."""
    def db_value(self) -> str:
        """Return the database representation of the Enum value."""
        if self.value is None:
             return 'NULL' ## Or handle None appropriately, maybe return None? Let's stick to NULL string for now as typical SQL.
        else:
            return f"'{self.value}'" 