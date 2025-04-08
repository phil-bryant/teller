from .teller_object import TellerObject
from .institution import TellerInstitution
from .account_links import TellerAccountLinks
from .enums import TellerAccountType, TellerAccountSubtype, TellerAccountStatus
from .account_details import TellerAccountDetails
from .account_balances import TellerAccountBalances
from .transaction import TellerTransaction
from typing import Optional

class TellerAccount(TellerObject): ## https://teller.io/docs/api/accounts
    _path: str = "/accounts"

    def __init__(self, api_data):
        super().__init__(api_data)
        self._set_field("currency", str, api_data)
        self._set_field("enrollment_id", str, api_data)
        self._set_field("id", str, api_data, {"pk": True, "db_name": "account_id"})
        self._set_field("institution", TellerInstitution, api_data, {"db_name": "institution_id", "fk": True})
        self._set_field("last_four", str, api_data, {"__str__": True})
        self._set_field("links", TellerAccountLinks, api_data, {"db_name": "account_links_id", "fk": True})
        self._set_field("name", str, api_data, {"__str__": True})
        self._set_field("type", TellerAccountType, api_data, {"enum": True})
        self._set_field("subtype", TellerAccountSubtype, api_data, {"__str__": True, "enum": True})
        self._set_field("status", TellerAccountStatus, api_data, {"enum": True})
        self._set_field("details", TellerAccountDetails, None, {}, self._api_client)
        self._set_field("balances", TellerAccountBalances, None, {}, self._api_client)
        self._set_field("transactions", TellerTransaction, None, {}, self._api_client)

    def institution_name(self) -> str:
        return self.institution.name if self.institution else ""
    
    def get_details(self) -> TellerAccountDetails:
        self.details = TellerAccountDetails(self._api_client.get(self.links.details))
        return self.details
    
    def get_transactions(self, limit: int = 2) -> list[TellerTransaction]:
        self.transactions = [TellerTransaction(td) for td in self._api_client.get(self.links.transactions, {'count': limit})]
        return self.transactions