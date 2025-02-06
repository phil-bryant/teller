from dataclasses import dataclass
from sqlalchemy import String, ForeignKey, BigInteger
from sqlalchemy.orm import Mapped, mapped_column, relationship
from teller_object import TellerObject
from teller_identity import TellerIdentity
from teller_list import TellerList
from teller_account import TellerAccount

@dataclass
class TellerAccountIdentities(TellerObject):
    account: Mapped[TellerAccount] = relationship()
    owners: Mapped[TellerList[TellerIdentity]] = relationship()
    account_identities_id: Mapped[int] = mapped_column(BigInteger, primary_key=True)
    account_id: Mapped[str] = mapped_column(String, ForeignKey("teller.account.account_id"))
