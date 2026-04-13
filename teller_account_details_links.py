from dataclasses import dataclass
from sqlalchemy import String, ForeignKey, BigInteger
from sqlalchemy.orm import Mapped, mapped_column
from teller_object import TellerObject

@dataclass
class TellerAccountDetailsLinks(TellerObject):
    self_link: Mapped[str] = mapped_column(String, unique=True, info={"api_name": "self"})
    account: Mapped[str] = mapped_column(String, unique=True)
    account_details_links_id: Mapped[int] = mapped_column(BigInteger, primary_key=True)