from dataclasses import dataclass, field
from teller_object import TellerObject
from teller_account import TellerAccount
from teller_identity import TellerIdentity
from teller_list import TellerList

@dataclass
class TellerAccountIdentities(TellerObject): ## https://teller.io/docs/api/identity#get-identity
    account: TellerAccount = field(default=None)
    owners: TellerList[TellerIdentity] = field(default=None)