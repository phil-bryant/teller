from dataclasses import dataclass, field
from teller_object import TellerObject

@dataclass
class TellerAccountBalancesLinks(TellerObject): ## https://teller.io/docs/api/account/balances
    self_link: str = field(default="")  ## self in API
    account: str = field(default="")

    def __post_init__(self):
        super().__post_init__()
        ## The Teller API calls this attribute "self" so we call it self_link avoiding conflict with the python reserved word, "self".
        self.self_link = self._api_data['self'] 