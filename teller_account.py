from typing import Any, Optional
from teller_object import TellerObject
from field import Field
from teller_institution import TellerInstitution
from teller_account_links import TellerAccountLinks
from teller_enums import TellerAccountType, TellerAccountSubtype, TellerAccountStatus
from teller_account_details import TellerAccountDetails
from teller_account_balances import TellerAccountBalances
from teller_list import TellerList
from teller_transaction import TellerTransaction

class TellerAccount(TellerObject): ## https://teller.io/docs/api/accounts

    def __init__(self, api_client: Optional[Any] = None, api_data: Optional[dict] = None):
        super().__init__(api_client, api_data)
        self._set_field("currency", str, api_data, {})
        self._set_field("enrollment_id", str, api_data, {})
        self._set_field("id", str, api_data, {"pk": True, "db_name": "account_id"})
        self._set_field("institution", TellerInstitution, api_data, {"fk": True})
        self._set_field("last_four", str, api_data, {"__str__": True})
        self._set_field("links", TellerAccountLinks, api_data, {"fk": True})
        self._set_field("name", str, api_data, {"__str__": True})
        self._set_field("type", TellerAccountType, api_data, {"enum": True})
        self._set_field("subtype", TellerAccountSubtype, api_data, {"__str__": True, "enum": True})
        self._set_field("status", TellerAccountStatus, api_data, {"enum": True})
        self._set_field("details", TellerAccountDetails, api_data, {})
        self._set_field("balances", TellerAccountBalances, api_data, {})
        self._set_field("transactions", TellerList[TellerTransaction], api_data, {})
    
    def institution_name(self) -> str:
        return self.institution.name if self.institution else ""
    
    def get_details(self) -> TellerAccountDetails:
        self.details = TellerAccountDetails(self._api_client.get(self.links.details))
        return self.details
    
    def get_transactions(self, count: int = None) -> TellerList[TellerTransaction]:
        self.transactions = [TellerTransaction(td) for td in self._api_client.get(self.links.transactions, {'count': count} if count else {})]
        return self.transactions