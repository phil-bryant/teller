from dataclasses import dataclass, field
from teller_object import TellerObject

@dataclass
class TellerInstitution(TellerObject): ## https://teller.io/docs/api/institutions
    institution_id: str = field(default="")
    name: str = field(default="") 