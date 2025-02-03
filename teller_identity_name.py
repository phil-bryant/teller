from dataclasses import dataclass, field
from teller_object import TellerObject
from teller_enums import TellerIdentityNameType

@dataclass
class TellerIdentityName(TellerObject): ## Defined on the Identity page: https://teller.io/docs/api/identity
    type: TellerIdentityNameType = field(default=None)
    data: str = field(default="") 