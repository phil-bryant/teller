from requests import Response
from teller_object import TellerObject

class TellerAccountDetailsLinks(TellerObject): ## https://teller.io/docs/api/account/details

    def __init__(self, api_data: dict):
        super().__init__()
        self._set_field("self_link", str, api_data, {"api_name": "self"}, )
        self._set_field("account", str, api_data, {"api_name": "account"}, )
        self._set_field("account_details_links_id", int, api_data, {"pk": True}, )

    def get_response(self):
        return Response(self.get(self.self_link))
