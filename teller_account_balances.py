from dataclasses import dataclass, field
from teller_object import TellerObject
from teller_account_balances_links import TellerAccountBalancesLinks

@dataclass
class TellerAccountBalances(TellerObject): ## https://teller.io/docs/api/account/balances
    ledger: str = field(default="", metadata={"__str__": True})
    links: TellerAccountBalancesLinks = field(default=None)
    account_id: str = field(default="")
    available: str = field(default="", metadata={"__str__": True})