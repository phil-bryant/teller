from teller_object import TellerObject
from dataclasses import dataclass

@dataclass
class TellerAccountDetailsLinks(TellerObject):
    details: str
    account: str
