from dataclasses import dataclass
from sqlalchemy import String, BigInteger, ForeignKey
from sqlalchemy.orm import Mapped, mapped_column, relationship
from .teller_object import TellerObject
from .teller_account_details_links import TellerAccountDetailsLinks
from .teller_routing_numbers import TellerRoutingNumbers
from typing import TYPE_CHECKING
if TYPE_CHECKING:
    from .teller_account import TellerAccount

@dataclass
class TellerAccountDetails(TellerObject): ## https://teller.io/docs/api/account/details
    account_id: Mapped[str] = mapped_column(String, ForeignKey("teller.account.account_id"))
    account_number: Mapped[str] = mapped_column(String, primary_key=True)
    links: Mapped[TellerAccountDetailsLinks] = relationship(
        primaryjoin="TellerAccountDetails.account_details_links_id == TellerAccountDetailsLinks.account_details_links_id"
    )
    routing_numbers: Mapped[TellerRoutingNumbers] = relationship(
        primaryjoin="TellerAccountDetails.routing_numbers_id == TellerRoutingNumbers.routing_numbers_id",
        uselist=False
    )
    account_details_links_id: Mapped[int] = mapped_column(BigInteger, ForeignKey("teller.account_details_links.account_details_links_id"), unique=True)
    routing_numbers_id: Mapped[int] = mapped_column(BigInteger, ForeignKey("teller.routing_numbers.routing_numbers_id"), nullable=True)
    account: Mapped["TellerAccount"] = relationship(
        "TellerAccount",
        primaryjoin="TellerAccountDetails.account_id == TellerAccount.id",
        foreign_keys="[TellerAccountDetails.account_id]",
        back_populates="details",
        uselist=False
    )