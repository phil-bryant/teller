from dataclasses import dataclass, field
from teller_object import TellerObject

@dataclass
class TellerEmail(TellerObject): ## Defined on the Identity page: https://teller.io/docs/api/identity
    data: str = field(default="") 