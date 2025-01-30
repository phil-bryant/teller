from dataclasses import dataclass, field
from teller_object import TellerObject

@dataclass
class TellerAddress(TellerObject):
    primary: bool = field(default=False)
    postal_code: str = field(default="")
    street: str = field(default="")
    region: str = field(default="")
    country: str = field(default="")
    city: str = field(default="") 