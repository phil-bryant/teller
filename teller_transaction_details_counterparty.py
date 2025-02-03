from dataclasses import dataclass, field
from teller_object import TellerObject
from teller_enums import TellerCounterpartyType

@dataclass
class TellerTransactionDetailsCounterparty(TellerObject): ## https://teller.io/docs/api/account/transactions
    name: str = field(default="")
    type: TellerCounterpartyType = field(default=None)