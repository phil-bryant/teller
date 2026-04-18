from dataclasses import dataclass
from sqlalchemy import String, BigInteger, ForeignKey, Enum
from sqlalchemy.orm import Mapped, mapped_column
from .teller_object import TellerObject
from .teller_enums import TellerIdentityNameType

@dataclass
class TellerIdentityName(TellerObject): ## https://teller.io/docs/api/identity
    type: Mapped[TellerIdentityNameType] = mapped_column(Enum(TellerIdentityNameType))
    data: Mapped[str] = mapped_column(String)
    identity_name_id: Mapped[int] = mapped_column(BigInteger, primary_key=True)
    identity_id: Mapped[int] = mapped_column(BigInteger, ForeignKey("teller.identity.identity_id")) 