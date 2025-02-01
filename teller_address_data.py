from dataclasses import dataclass, field
from teller_object import TellerObject

@dataclass
class TellerAddressData(TellerObject):
    postal_code: str = field(default="")
    street: str = field(default="")
    region: str = field(default="")
    country: str = field(default="")
    city: str = field(default="") 