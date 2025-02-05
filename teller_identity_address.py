from dataclasses import dataclass
from sqlalchemy import Boolean, BigInteger, ForeignKey
from sqlalchemy.orm import Mapped, mapped_column, relationship
from teller_object import TellerObject
from teller_identity_address_data import TellerIdentityAddressData

@dataclass
class TellerIdentityAddress(TellerObject): ## https://teller.io/docs/api/identity
    primary: Mapped[bool] = mapped_column(Boolean, default=False)
    data: Mapped[TellerIdentityAddressData] = relationship()