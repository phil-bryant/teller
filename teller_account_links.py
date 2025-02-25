from teller_object import TellerObject

class TellerAccountLinks(TellerObject): ## https://teller.io/docs/api/accounts
def __init__(self, api_data: dict):
        super().__init__()
        self._set_field("self_link", str, api_data, {"api_name": "self"})
        self._set_field("details", str, api_data, {})
        self._set_field("balances", str, api_data, {})
        self._set_field("transactions", str, api_data, {})
        self._set_field("account_links_id", int, None, {"pk": True})