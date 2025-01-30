from dataclasses import dataclass, field
from teller_object import TellerObject

@dataclass
class TellerTransactionLinks(TellerObject):
    self_link: str = field(default="")
    account: str = field(default="")
    details: str = field(default="")

    def __post_init__(self):
        super().__post_init__()
        if 'self' in self.api_data:
            self.self_link = self.api_data['self'] 