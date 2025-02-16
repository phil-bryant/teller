from teller_object import TellerObject
from annotation import Annotation

class TellerAccountBalancesLinks(TellerObject): ## https://teller.io/docs/api/account/balances
    self_link: Annotation[str, ({"api_name": "self"}, )] = ""
    account_link: Annotation[str, ({"api_name": "account"}, )] = ""
    account_balances_links_id: Annotation[int, ({"pk": True}, )] = None