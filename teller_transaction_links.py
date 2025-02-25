from teller_object import TellerObject

class TellerTransactionLinks(TellerObject): ## https://teller.io/docs/api/account/transactions

    def __init__(self, api_data: dict):
        super().__init__()
        self._set_field("self_link", str, api_data, {"api_name": "self"})
        self._set_field("account", str, api_data)
        self._set_field("transaction_links_id", int, None, {"pk": True})
