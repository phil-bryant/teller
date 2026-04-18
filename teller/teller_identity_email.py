from dataclasses import dataclass
from sqlalchemy import String, BigInteger, ForeignKey
from sqlalchemy.orm import Mapped, mapped_column
from .teller_object import TellerObject

@dataclass
class TellerIdentityEmail(TellerObject): ## https://teller.io/docs/api/identity
    data: Mapped[str] = mapped_column(String, unique=True)
    identity_email_id: Mapped[int] = mapped_column(BigInteger, primary_key=True)
    identity_id: Mapped[int] = mapped_column(BigInteger, ForeignKey("teller.identity.identity_id")) 