from dataclasses import dataclass, field
from teller_object import TellerObject

@dataclass
class TellerTransactionType(TellerObject):
    code: str = field(default="")

    def __str__(self):
        return self.code 