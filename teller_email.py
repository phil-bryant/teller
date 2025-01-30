from dataclasses import dataclass, field
from teller_object import TellerObject

@dataclass
class TellerEmail(TellerObject):
    data: str = field(default="") 