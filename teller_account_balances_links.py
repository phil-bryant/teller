from dataclasses import dataclass
from sqlalchemy import String, BigInteger
from sqlalchemy.orm import Mapped, mapped_column
from teller_object import TellerObject

@dataclass
class TellerAccountBalancesLinks(TellerObject): ## https://teller.io/docs/api/account/balances
    self_link: Mapped[str] = mapped_column(String, unique=True, info={"api_name": "self"})
    account_link: Mapped[str] = mapped_column(String, unique=True, name="account")
    account_balances_links_id: Mapped[int] = mapped_column(BigInteger, primary_key=True)