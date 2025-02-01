from dataclasses import dataclass, field
from teller_object import TellerObject
from teller_address_data import TellerAddressData

@dataclass 
class TellerAddress(TellerObject):
    primary: bool = field(default=False)
    data: TellerAddressData = field(default=None)

   