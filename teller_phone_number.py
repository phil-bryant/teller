from dataclasses import dataclass, field
from teller_object import TellerObject
from teller_enums import TellerPhoneType

@dataclass
class TellerPhoneNumber(TellerObject):
    type: TellerPhoneType = field(default=None)
    data: str = field(default="") 