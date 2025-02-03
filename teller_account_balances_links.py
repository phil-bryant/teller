from dataclasses import dataclass, field
from teller_object import TellerObject

@dataclass
class TellerAccountBalancesLinks(TellerObject): ## https://teller.io/docs/api/account/balances
    self_link: str = field(default="", metadata={"api_name": "self"})
    account: str = field(default="")