from dataclasses import dataclass
from sqlalchemy import String, BigInteger, ForeignKey
from sqlalchemy.orm import Mapped, mapped_column, relationship
from teller_object import TellerObject
from teller_account_details_links import TellerAccountDetailsLinks
from teller_routing_numbers import TellerRoutingNumbers

@dataclass
class TellerAccountDetails(TellerObject): ## https://teller.io/docs/api/account/details
    account_id: Mapped[str] = mapped_column(String, ForeignKey("teller.account.account_id"), primary_key=True)
    account_number: Mapped[str] = mapped_column(String, unique=True)
    links: Mapped[TellerAccountDetailsLinks] = relationship()
    routing_numbers: Mapped[TellerRoutingNumbers] = relationship()
