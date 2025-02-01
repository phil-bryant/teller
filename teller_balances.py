from dataclasses import dataclass, field
from teller_object import TellerObject
from teller_account_balances_links import TellerAccountBalancesLinks

@dataclass
class TellerBalances(TellerObject):
    account_id: str = field(default="")
    ledger: str = field(default="")
    available: str = field(default="")
    links: TellerAccountBalancesLinks = field(default=None)

    def __str__(self):
        return f"Ledger: {self.ledger}, Available: {self.available}" 