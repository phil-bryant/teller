from teller_object import TellerObject
from annotation import Annotation

class TellerTransactionLinks(TellerObject): ## https://teller.io/docs/api/account/transactions
    self_link: Annotation[str, ({"api_name": "self"}, )] = ""
    account: Annotation[str, ({}, )] = ""
    transaction_links_id: Annotation[int, ({"pk": True}, )] = None