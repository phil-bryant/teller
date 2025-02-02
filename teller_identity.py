from dataclasses import dataclass, field
from typing import List
from teller_object import TellerObject
from teller_enums import TellerIdentityType
from teller_name import TellerName
from teller_address import TellerAddress
from teller_phone_number import TellerPhoneNumber
from teller_email import TellerEmail

@dataclass
class TellerIdentity(TellerObject): ## https://teller.io/docs/api/identity
    type: TellerIdentityType = field(default=None)
    names: list[TellerName] = field(default_factory=list)
    addresses: list[TellerAddress] = field(default_factory=list)
    phone_numbers: list[TellerPhoneNumber] = field(default_factory=list)
    emails: list[TellerEmail] = field(default_factory=list)