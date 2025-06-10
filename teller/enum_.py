from enum import Enum

class TellerEnum(Enum):
    def db_value(self) -> str:
        return 'NULL' if self.value is None else f"'{self.value}'"
    
    def constrains(self, aTellerObject) -> bool:
        return False

    def save(self):
        pass
