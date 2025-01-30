from teller_object import TellerObject
from dataclasses import dataclass, field
from typing import Dict

@dataclass
class TellerAccountLinks(TellerObject):
    self_link: str = field(default="")
    details: str = field(default="")
    balances: str = field(default="")
    transactions: str = field(default="")

    def __post_init__(self):
        super().__post_init__()
        if 'self' in self.api_data:
            self.self_link = self.api_data['self']
