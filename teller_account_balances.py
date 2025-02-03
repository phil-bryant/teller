from dataclasses import dataclass, field
from decimal import Decimal
from teller_object import TellerObject
from teller_account_balances_links import TellerAccountBalancesLinks

@dataclass
class TellerAccountBalances(TellerObject):
    ledger: Decimal = field(default_factory=lambda: Decimal('0.00'), metadata={"__str__": True})
    links: TellerAccountBalancesLinks = field(default=None)
    account_id: str = field(default="")
    available: Decimal = field(default_factory=lambda: Decimal('0.00'), metadata={"__str__": True})