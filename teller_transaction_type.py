from dataclasses import dataclass, field
from teller_object import TellerObject

@dataclass
class TellerTransactionType(TellerObject):
    id: int = field(default=0)
    code: str = field(default="")

    def __str__(self):
        return self.code 