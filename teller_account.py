from dataclasses import dataclass, field
from teller_object import TellerObject
from teller_institution import TellerInstitution
from teller_account_links import TellerAccountLinks
from teller_enums import TellerAccountType, TellerAccountSubtype, TellerAccountStatus
from teller_account_details import TellerAccountDetails
from teller_balances import TellerBalances
from teller_transaction import TellerTransaction

@dataclass
class TellerAccount(TellerObject):
    currency: str = field(default="")
    enrollment_id: str = field(default="")
    id: str = field(default="")
    institution: TellerInstitution = field(default=None)
    last_four: str = field(default="")
    links: TellerAccountLinks = field(default=None)
    name: str = field(default="")
    type: TellerAccountType = field(default=None)
    subtype: TellerAccountSubtype = field(default=None)
    status: TellerAccountStatus = field(default=None)
    details: TellerAccountDetails = field(default=None)
    balances: TellerBalances = field(default=None)
    transactions: list[TellerTransaction] = field(default_factory=list)
    
    def institution_name(self) -> str:
        return self.institution.name if self.institution else ""
    
    def get_details(self) -> TellerAccountDetails:
        self.details = TellerAccountDetails(self._api_client.get(self.links.details))
        return self.details
    
    def get_transactions(self, count: int = None) -> list[TellerTransaction]:
        self.transactions = [TellerTransaction(td) for td in self._api_client.get(self.links.transactions, {'count': count} if count else {})]
        return self.transactions
    
    def __str__(self):
        return f"{self.institution_name()} {self.name} ({self.subtype}) {self.last_four}" 