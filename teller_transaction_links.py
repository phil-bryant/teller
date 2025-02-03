from dataclasses import dataclass, field
from teller_object import TellerObject

@dataclass
class TellerTransactionLinks(TellerObject): ## https://teller.io/docs/api/account/transactions
    self_link: str = field(default="")
    account: str = field(default="")

    def __post_init__(self):
        super().__post_init__()
        if 'self' in self._api_data:
            ## The Teller API calls this attribute "self" so we call it self_link to avoid conflict with the python reserved word, "self".
            self.self_link = self._api_data['self'] 