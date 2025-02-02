from dataclasses import dataclass, field
from teller_object import TellerObject

@dataclass
class TellerAddressData(TellerObject):
    street: str = field(default="")
    city: str = field(default="") 
    region: str = field(default="")
    postal_code: str = field(default="")
    country: str = field(default="")