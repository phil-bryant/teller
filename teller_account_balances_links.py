from dataclasses import dataclass, field
from teller_object import TellerObject

@dataclass
class TellerAccountBalancesLinks(TellerObject):
    self_link: str = field(default="")
    account: str = field(default="")

    def __post_init__(self):
        super().__post_init__()
        ## Unfortunately Teller API calls this attribute "self" so we have to call it self_link due to the python reserved word, "self".
        self.self_link = self._api_data['self'] 