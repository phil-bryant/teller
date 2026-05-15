from dataclasses import dataclass
from sqlalchemy import Boolean, BigInteger, ForeignKey
from sqlalchemy.orm import Mapped, mapped_column
from .teller_object import TellerObject
from .teller_identity_address_data import TellerIdentityAddressData

@dataclass
class TellerIdentityAddress(TellerObject): ## https://teller.io/docs/api/identity
    primary: Mapped[bool] = mapped_column(Boolean, default=False, name="primary_address")
    data: Mapped[TellerIdentityAddressData] = mapped_column(BigInteger, ForeignKey("teller.identity_address_data.identity_address_data_id"))
    identity_address_id: Mapped[int] = mapped_column(BigInteger, primary_key=True)
    identity_id: Mapped[int] = mapped_column(BigInteger, ForeignKey("teller.identity.identity_id"))
