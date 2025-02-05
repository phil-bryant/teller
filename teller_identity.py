from dataclasses import dataclass
from sqlalchemy import BigInteger, Enum
from sqlalchemy.orm import Mapped, mapped_column, relationship
from teller_object import TellerObject
from teller_enums import TellerIdentityType
from teller_identity_name import TellerIdentityName
from teller_identity_address import TellerIdentityAddress
from teller_identity_phone_number import TellerIdentityPhoneNumber
from teller_identity_email import TellerIdentityEmail
from typing import List

@dataclass
class TellerIdentity(TellerObject): ## https://teller.io/docs/api/identity
    type: Mapped[TellerIdentityType] = mapped_column(Enum(TellerIdentityType))
    identity_id: Mapped[int] = mapped_column(BigInteger, primary_key=True)
    names: Mapped[List["TellerIdentityName"]] = relationship()
    addresses: Mapped[List["TellerIdentityAddress"]] = relationship()
    phone_numbers: Mapped[List["TellerIdentityPhoneNumber"]] = relationship()
    emails: Mapped[List["TellerIdentityEmail"]] = relationship()