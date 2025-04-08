from .teller_object import TellerObject
from typing import Optional

class TellerAccountBalancesLinks(TellerObject): ## https://teller.io/docs/api/account/balances

    def __init__(self, api_data: dict):
        super().__init__()
        self._set_field("self_link", str, api_data, {"api_name": "self"})
        self._set_field("account_link", str, api_data, {"api_name": "account"})
        self._set_field("account_balances_links_id", int, None, {"pk": True})
