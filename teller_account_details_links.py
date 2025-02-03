from teller_object import TellerObject
from dataclasses import dataclass, field

@dataclass
class TellerAccountDetailsLinks(TellerObject): ## https://teller.io/docs/api/account/details
    self_link: str = field(default="", metadata={"api_name": "self"})
    account: str = field(default="")
