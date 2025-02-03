from dataclasses import dataclass, field
from teller_object import TellerObject
from teller_enums import TellerIdentityPhoneNumberType

@dataclass
class TellerIdentityPhoneNumber(TellerObject): ## Defined on the Identity page: https://teller.io/docs/api/identity
    type: TellerIdentityPhoneNumberType = field(default=None)
    data: str = field(default="") 