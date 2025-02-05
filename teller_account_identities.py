from dataclasses import dataclass
from sqlalchemy import String, ForeignKey
from sqlalchemy.orm import Mapped, mapped_column, relationship
from teller_object import TellerObject
from teller_identity import TellerIdentity
from typing import List

@dataclass
class TellerAccountIdentities(TellerObject): ## https://teller.io/docs/api/identity#get-identity
    account: Mapped[str] = mapped_column(String, ForeignKey("teller.account.account_id"), primary_key=True)
    owners: Mapped[List[TellerIdentity]] = relationship(secondary="teller.account_identities")