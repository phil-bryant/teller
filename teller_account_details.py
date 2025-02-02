from dataclasses import dataclass, field
from teller_object import TellerObject
from teller_account_details_links import TellerAccountDetailsLinks
from teller_routing_numbers import TellerRoutingNumbers

@dataclass
class TellerAccountDetails(TellerObject):
    account_id: str = field(default="")
    account_number: str = field(default="")    
    links: TellerAccountDetailsLinks = field(default=None)
    routing_numbers: TellerRoutingNumbers = field(default=None)
