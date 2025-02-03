from dataclasses import dataclass, field
from teller_object import TellerObject
from teller_list import TellerList
from teller_enums import TellerIdentityType
from teller_identity_name import TellerIdentityName
from teller_identity_address import TellerIdentityAddress
from teller_identity_phone_number import TellerIdentityPhoneNumber
from teller_identity_email import TellerIdentityEmail

@dataclass
class TellerIdentity(TellerObject): ## https://teller.io/docs/api/identity
    type: TellerIdentityType = field(default=None)
    names: TellerList[TellerIdentityName] = field(default_factory=list)
    addresses: TellerList[TellerIdentityAddress] = field(default_factory=list)
    phone_numbers: TellerList[TellerIdentityPhoneNumber] = field(default_factory=list)
    emails: TellerList[TellerIdentityEmail] = field(default_factory=list)