from dataclasses import dataclass, field
from teller_object import TellerObject

@dataclass
class TellerRoutingNumbers(TellerObject): ## https://teller.io/docs/api/account/details
    ach: str = field(default="")
    wire: str = field(default="")
    bacs: str = field(default="") 