from dataclasses import dataclass, field
from teller_object import TellerObject
from teller_account import TellerAccount
from teller_identity import TellerIdentity

@dataclass
class TellerAccountIdentities(TellerObject): ## https://teller.io/docs/api/identity#get-identity
    account: TellerAccount = field(default=None)
    owners: list[TellerIdentity] = field(default=None)