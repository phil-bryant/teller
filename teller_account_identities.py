from dataclasses import dataclass, field
from typing import List
from teller_account import TellerAccount
from teller_identity import TellerIdentity
from teller_object import TellerObject

@dataclass
class TellerAccountIdentities(TellerObject):
    account: TellerAccount = field(default=None)
    owners: list[TellerIdentity] = field(default_factory=list)