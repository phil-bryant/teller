from teller_object import TellerObject
from dataclasses import dataclass, field

@dataclass
class TellerAccountDetailsLinks(TellerObject): ## https://teller.io/docs/api/account/details
    self_link: str = field(default="")  ## self in API
    account: str = field(default="")

    def __post_init__(self):
        super().__post_init__()
        ## The Teller API calls this attribute "self" so we call it self_link to avoidconflict with python reserved word, "self".
        self.self_link = self._api_data['self']