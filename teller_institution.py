from dataclasses import dataclass, field
from teller_object import TellerObject

@dataclass
class TellerInstitution(TellerObject):
    id: str = field(default="")
    name: str = field(default="") 