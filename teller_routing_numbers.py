from dataclasses import dataclass, field
from teller_object import TellerObject

@dataclass
class TellerRoutingNumbers(TellerObject):
    ach: str = field(default="")
    wire: str = field(default="")
    bacs: str = field(default="") 