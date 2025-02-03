from dataclasses import dataclass, field
from typing import List
from teller_object import TellerObject
from teller_enums import TellerIdentityType
from teller_identity_name import TellerIdentityName
from teller_identity_address import TellerIdentityAddress
from teller_identity_phone_number import TellerIdentityPhoneNumber
from teller_identity_email import TellerIdentityEmail

@dataclass
class TellerIdentity(TellerObject): ## https://teller.io/docs/api/identity
    type: TellerIdentityType = field(default=None)
    names: list[TellerIdentityName] = field(default_factory=list)
    addresses: list[TellerIdentityAddress] = field(default_factory=list)
    phone_numbers: list[TellerIdentityPhoneNumber] = field(default_factory=list)
    emails: list[TellerIdentityEmail] = field(default_factory=list)