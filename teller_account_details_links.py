from requests import Response
from teller_object import TellerObject
from annotation import Annotation

class TellerAccountDetailsLinks(TellerObject): ## https://teller.io/docs/api/account/details
    self_link: Annotation[str, ({"api_name": "self"}, )] = ""
    account: Annotation[str, ({"api_name": "account"}, )] = ""
    account_details_links_id: Annotation[int, ({"pk": True}, )] = None

    def get_response(self):
        return Response(self.get(self.self_link))
