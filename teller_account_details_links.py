from dataclasses import dataclass
from sqlalchemy import String, ForeignKey
from sqlalchemy.orm import Mapped, mapped_column
from teller_object import TellerObject

@dataclass
class TellerAccountDetailsLinks(TellerObject):
    account_id: Mapped[str] = mapped_column(String, ForeignKey("teller.account.account_id"), primary_key=True)
    details_id: Mapped[str] = mapped_column(String, ForeignKey("teller.account_details.details_id"), primary_key=True)
