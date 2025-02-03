from dataclasses import dataclass, field
from teller_object import TellerObject
from teller_account_balances_links import TellerAccountBalancesLinks

@dataclass
class TellerBalances(TellerObject): ## https://teller.io/docs/api/account/balances
    ledger: str = field(default="")
    links: TellerAccountBalancesLinks = field(default=None)
    account_id: str = field(default="")
    available: str = field(default="")

    def __str__(self):
        return f"Ledger: {self.ledger}, Available: {self.available}" 