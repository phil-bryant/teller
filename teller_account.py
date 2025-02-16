from typing import List
from teller_object import TellerObject
from annotation import Annotation
from teller_institution import TellerInstitution
from teller_account_links import TellerAccountLinks
from teller_enums import TellerAccountType, TellerAccountSubtype, TellerAccountStatus
from teller_account_details import TellerAccountDetails
from teller_account_balances import TellerAccountBalances
from teller_transaction import TellerTransaction

class TellerAccount(TellerObject): ## https://teller.io/docs/api/accounts
    currency: Annotation[str, ({}, )] = ""
    enrollment_id: Annotation[str, ({}, )] = ""
    id: Annotation[str, ({"pk": True, "db_name": "account_id"}, )] = ""
    institution: Annotation[TellerInstitution, ({"fk": True}, )] = None
    last_four: Annotation[str, ({"__str__": True}, )] = ""
    links: Annotation[TellerAccountLinks, ({"fk": True}, )] = None
    name: Annotation[str, ({"__str__": True}, )] = ""
    type: Annotation[TellerAccountType, ({"enum": True}, )] = None
    subtype: Annotation[TellerAccountSubtype, ({"__str__": True, "enum": True}, )] = None
    status: Annotation[TellerAccountStatus, ({"enum": True}, )] = None
    details: Annotation[TellerAccountDetails, ({}, )] = None
    balances: Annotation[TellerAccountBalances, ({}, )] = None
    transactions: Annotation[List[TellerTransaction], ({}, )] = []

    def __init__(self, api_data: dict):
        super().__init__(api_data)
    
    def institution_name(self) -> str:
        return self.institution.name if self.institution else ""
    
    def get_details(self) -> TellerAccountDetails:
        self.details = TellerAccountDetails(self._api_client.get(self.links.details))
        return self.details
    
    def get_transactions(self, count: int = None) -> List[TellerTransaction]:
        self.transactions = [TellerTransaction(td) for td in self._api_client.get(self.links.transactions, {'count': count} if count else {})]
        return self.transactions