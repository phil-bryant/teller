from dataclasses import dataclass, field
from teller_object import TellerObject

## Physical address data associated with an Address
## This design allows multiple people to share an address independent of primary designation
## Defined on the Identity page: https://teller.io/docs/api/identity
@dataclass
class TellerIdentityAddressData(TellerObject):
    street: str = field(default="")
    city: str = field(default="") 
    region: str = field(default="")
    postal_code: str = field(default="")
    country: str = field(default="")