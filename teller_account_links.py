from teller_object import TellerObject
from annotation import Annotation

class TellerAccountLinks(TellerObject): ## https://teller.io/docs/api/accounts
    self_link: Annotation[str, ({"api_name": "self"}, )] = ""
    details: Annotation[str, ({}, )] = ""
    balances: Annotation[str, ({}, )] = ""
    transactions: Annotation[str, ({}, )] = ""
    account_links_id: Annotation[int, ({"pk": True}, )] = None