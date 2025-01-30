from dataclasses import dataclass, field
from teller_object import TellerObject
from teller_enums import TellerCounterpartyType

@dataclass
class TellerTransactionCounterparty(TellerObject):
    name: str = field(default="")
    type: TellerCounterpartyType = field(default=None)
    routing_number: str = field(default="")
    account_number: str = field(default="") 