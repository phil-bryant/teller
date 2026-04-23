from dataclasses import dataclass
from sqlalchemy import String, BigInteger
from sqlalchemy.orm import Mapped, mapped_column
from teller_object import TellerObject

@dataclass
class TellerAccountLinks(TellerObject): ## https://teller.io/docs/api/accounts
    self_link: Mapped[str] = mapped_column(String, info={"api_name": "self"})
    details: Mapped[str] = mapped_column(String, nullable=True)
    balances: Mapped[str] = mapped_column(String, nullable=True)
    transactions: Mapped[str] = mapped_column(String, nullable=True)
    account_links_id: Mapped[int] = mapped_column(BigInteger, primary_key=True)
