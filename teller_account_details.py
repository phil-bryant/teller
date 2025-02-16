from teller_object import TellerObject
from annotation import Annotation
from teller_account_details_links import TellerAccountDetailsLinks
from teller_routing_numbers import TellerRoutingNumbers

class TellerAccountDetails(TellerObject): ## https://teller.io/docs/api/account/details
    account_id: Annotation[str, ({"pk": True, "fk": True}, )] = ""
    account_number: Annotation[str, ({}, )] = ""    
    links: Annotation[TellerAccountDetailsLinks, ({}, )] = None
    routing_numbers: Annotation[TellerRoutingNumbers, ({}, )] = None
