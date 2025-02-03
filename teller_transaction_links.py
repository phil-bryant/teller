from dataclasses import dataclass, field
from teller_object import TellerObject

@dataclass
class TellerTransactionLinks(TellerObject): ## https://teller.io/docs/api/account/transactions
    self_link: str = field(default="", metadata={"api_name": "self"})
    account: str = field(default="")