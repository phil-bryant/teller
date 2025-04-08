from .utils.iso_date import ISODate
from .teller_object import TellerObject
from .account_balances_links import TellerAccountBalancesLinks
from typing import Optional
from decimal import Decimal

class TellerAccountBalances(TellerObject):
    def __init__(self, api_data: dict):
        super().__init__(api_data)
        self._set_field("account_id", str, api_data, {"fk": True})
        self._set_field("ledger", Decimal, api_data, {"__str__": True})
        self._set_field("available", Decimal, api_data, {"__str__": True})
        self._set_field("links", TellerAccountBalancesLinks, api_data)
        self._set_field("account_balances_id", int, None, {"pk": True})