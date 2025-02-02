from dataclasses import dataclass, field
from teller_object import TellerObject

@dataclass
class TellerInstitutions(TellerObject): ## Shape mirrors https://teller.io/docs/api/institutions
    id: str = field(default="")
    name: str = field(default="") 