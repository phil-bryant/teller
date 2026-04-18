from dataclasses import dataclass
from sqlalchemy import String, BigInteger
from sqlalchemy.orm import Mapped, mapped_column
from .teller_object import TellerObject

@dataclass
class TellerTransactionLinks(TellerObject): ## https://teller.io/docs/api/account/transactions
    self_link: Mapped[str] = mapped_column(String, unique=True, info={"api_name": "self"})
    account: Mapped[str] = mapped_column(String, unique=True)
    transaction_links_id: Mapped[int] = mapped_column(BigInteger, primary_key=True)