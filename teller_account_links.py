from dataclasses import dataclass, field
from teller_object import TellerObject

@dataclass
class TellerAccountLinks(TellerObject): ## https://teller.io/docs/api/accounts
    self_link: str = field(default="", metadata={"api_name": "self"})
    details: str = field(default="")
    balances: str = field(default="")
    transactions: str = field(default="")