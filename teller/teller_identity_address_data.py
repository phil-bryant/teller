from dataclasses import dataclass
from sqlalchemy import String, BigInteger
from sqlalchemy.orm import Mapped, mapped_column
from .teller_object import TellerObject

## Physical address data associated with an Address
## This design allows multiple people to share an address independent of primary designation
## Defined on the Identity page: https://teller.io/docs/api/identity
@dataclass
class TellerIdentityAddressData(TellerObject):
    street: Mapped[str] = mapped_column(String)
    city: Mapped[str] = mapped_column(String)
    region: Mapped[str] = mapped_column(String)
    country: Mapped[str] = mapped_column(String(2))
    postal_code: Mapped[str] = mapped_column(String)
    identity_address_data_id: Mapped[int] = mapped_column(BigInteger, primary_key=True)