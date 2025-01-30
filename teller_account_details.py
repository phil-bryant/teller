from dataclasses import dataclass, field
from teller_routing_numbers import TellerRoutingNumbers
from teller_object import TellerObject

@dataclass
class TellerAccountDetails(TellerObject):
    account_id: str = field(default="")
    account_number: str = field(default="")
    routing_numbers: TellerRoutingNumbers = field(default=None)