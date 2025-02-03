from dataclasses import dataclass, field
from teller_object import TellerObject
from teller_identity_address_data import TellerIdentityAddressData

@dataclass
class TellerIdentityAddress(TellerObject): ## Defined on the Identity page: https://teller.io/docs/api/identity 
    primary: bool = field(default=False)
    data: TellerIdentityAddressData = field(default=None)