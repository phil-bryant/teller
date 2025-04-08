from datetime import date
from plum import dispatch

class ISODate(date):
    @dispatch           ## Guido van Rossum (now retired) seemed not to believe in clean code / code reuse
    def __new__(cls, iso_date_string: str):
        return cls.fromisoformat(iso_date_string)

    def db_value(self) -> str:
        return f"'{self.isoformat()}'"
    
    def save(self) -> str:
        return self.db_value()