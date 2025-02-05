from dataclasses import dataclass
from sqlalchemy import String, BigInteger, ForeignKey, Numeric
from sqlalchemy.orm import Mapped, mapped_column, relationship
from teller_object import TellerObject
from teller_account_balances_links import TellerAccountBalancesLinks

@dataclass
class TellerAccountBalances(TellerObject):
    account_id: Mapped[str] = mapped_column(String, ForeignKey("teller.account.account_id"))
    ledger: Mapped[float] = mapped_column(Numeric(15,2), nullable=True)
    account_balances_links_id: Mapped[int] = mapped_column(BigInteger, ForeignKey("teller.account_balances_links.account_balances_links_id"))
    available: Mapped[float] = mapped_column(Numeric(15,2), nullable=True)
    account_balances_id: Mapped[int] = mapped_column(BigInteger, primary_key=True)
    links: Mapped[TellerAccountBalancesLinks] = relationship()