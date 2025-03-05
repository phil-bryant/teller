from decimal import Decimal
from teller_object import TellerObject
from teller_account_balances_links import TellerAccountBalancesLinks

class TellerAccountBalances(TellerObject):
    def __init__(self, api_data: dict):
        super().__init__(api_data)
        self._set_field("account_id", str, api_data, {"fk": True})
        self._set_field("ledger", Decimal, api_data, {"__str__": True})
        self._set_field("available", Decimal, api_data, {"__str__": True})
        self._set_field("links", TellerAccountBalancesLinks, api_data)
        self._set_field("account_balances_id", int, None, {"pk": True})