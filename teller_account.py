from dataclasses import dataclass, field
from teller_object import TellerObject
from teller_institution import TellerInstitution
from teller_account_links import TellerAccountLinks
from teller_enums import TellerAccountType, TellerAccountSubtype, TellerAccountStatus
from teller_account_details import TellerAccountDetails
from teller_account_balances import TellerAccountBalances
from teller_transaction import TellerTransaction

@dataclass
class TellerAccount(TellerObject): ## https://teller.io/docs/api/accounts
    currency: str = field(default="")
    enrollment_id: str = field(default="")
    id: str = field(default="")
    institution: TellerInstitution = field(default=None)
    last_four: str = field(default="", metadata={"__str__": True})
    links: TellerAccountLinks = field(default=None)
    name: str = field(default="", metadata={"__str__": True})
    type: TellerAccountType = field(default=None)
    subtype: TellerAccountSubtype = field(default=None, metadata={"__str__": True})
    status: TellerAccountStatus = field(default=None)
    details: TellerAccountDetails = field(default=None)
    balances: TellerAccountBalances = field(default=None)
    transactions: list[TellerTransaction] = field(default_factory=list)
    
    def institution_name(self) -> str:
        return self.institution.name if self.institution else ""
    
    def get_details(self) -> TellerAccountDetails:
        self.details = TellerAccountDetails(self._api_client.get(self.links.details))
        return self.details
    
    def get_transactions(self, count: int = None) -> list[TellerTransaction]:
        self.transactions = [TellerTransaction(td) for td in self._api_client.get(self.links.transactions, {'count': count} if count else {})]
        return self.transactions