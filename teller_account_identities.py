from dataclasses import dataclass, field
from teller_object import TellerObject
from teller_accounts import TellerAccount
from teller_identity import TellerIdentity

@dataclass
class TellerAccountIdentities(TellerObject):
    account: TellerAccount = field(default=None)
    owners: list[TellerIdentity] = field(default=None)