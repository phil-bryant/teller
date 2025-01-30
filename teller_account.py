from typing import Dict, List, Optional
from dataclasses import dataclass, field
from teller_enums import TellerAccountType, TellerAccountSubtype, TellerAccountStatus
from teller_account_links import TellerAccountLinks
from teller_institution import TellerInstitution
from teller_transaction import TellerTransaction
from teller_object import TellerObject
from teller_balances import TellerBalances


@dataclass
class TellerAccount(TellerObject):
    type: TellerAccountType = field(default=None)
    subtype: TellerAccountSubtype = field(default=None)
    status: TellerAccountStatus = field(default=None)
    name: str = field(default="")
    links: TellerAccountLinks = field(default=None)
    last_four: str = field(default="")
    institution: TellerInstitution = field(default=None)
    id: str = field(default="")
    enrollment_id: str = field(default="")
    currency: str = field(default="")
    transactions: list[TellerTransaction] = field(default_factory=list)
    
    def institution_name(self) -> str:
        return self.institution.name if self.institution else ""
    
    def get_transactions(self, count: int = None) -> list[TellerTransaction]:
        self.transactions([TellerTransaction(td) for td in self.api_client.get(self.links.transactions, {'count': count} if count else {})])
        return self.transactions
    
    def __str__(self):
        return f"{self.institution_name()} {self.name} ({self.subtype}) {self.last_four}" 