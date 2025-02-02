from dataclasses import dataclass, field
from teller_object import TellerObject
from teller_address_data import TellerAddressData

@dataclass
class TellerAddress(TellerObject): ## Defined on the Identity page: https://teller.io/docs/api/identity 
    primary: bool = field(default=False)
    data: TellerAddressData = field(default=None)

   