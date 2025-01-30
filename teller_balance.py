from dataclasses import dataclass, field
from teller_object import TellerObject
from teller_account_balances_links import TellerAccountBalancesLinks

@dataclass
class TellerBalance(TellerObject):
    ledger: str = field(default="0.00")
    available: str = field(default="0.00")
    account_id: str = field(default=None)
    links: TellerAccountBalancesLinks = field(default=None)

    def __str__(self):
        return f"{self.ledger} ledger {self.available} available" 