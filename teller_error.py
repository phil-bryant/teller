from dataclasses import dataclass, field
from teller_object import TellerObject

@dataclass
class TellerError(TellerObject):
    code: str = field(default="")
    message: str = field(default="") 