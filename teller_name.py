from dataclasses import dataclass, field
from teller_object import TellerObject
from teller_enums import TellerNameType

@dataclass
class TellerName(TellerObject):
    type: TellerNameType = field(default=None)
    data: str = field(default="") 