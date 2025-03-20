from teller_object import TellerObject
from teller_account_details_links import TellerAccountDetailsLinks
from teller_routing_numbers import TellerRoutingNumbers

class TellerAccountDetails(TellerObject): ## https://teller.io/docs/api/account/details

    def __init__(self, api_data: dict):
        super().__init__(api_data)
        self._set_field("account_id", str, None, {"pk": True, "fk": True})
        self._set_field("account_number", str, api_data)
        self._set_field("links", TellerAccountDetailsLinks, api_data, {"fk": True, "db_ro": True})
        self._set_field("routing_numbers", TellerRoutingNumbers, api_data, {"fk": True, "db_ro": True})

