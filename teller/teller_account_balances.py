from dataclasses import dataclass
from sqlalchemy import String, BigInteger, ForeignKey, Numeric
from sqlalchemy.orm import Mapped, mapped_column, relationship
from .teller_object import TellerObject
from .teller_account_balances_links import TellerAccountBalancesLinks
from typing import TYPE_CHECKING
if TYPE_CHECKING:
    from .teller_account import TellerAccount

@dataclass
class TellerAccountBalances(TellerObject):
    account_id: Mapped[str] = mapped_column(String, ForeignKey("teller.account.account_id"))
    ledger: Mapped[float] = mapped_column(Numeric(15,2), nullable=True)
    available: Mapped[float] = mapped_column(Numeric(15,2), nullable=True)
    links: Mapped[TellerAccountBalancesLinks] = relationship()
    account_balances_id: Mapped[int] = mapped_column(BigInteger, primary_key=True)
    account_balances_links_id: Mapped[int] = mapped_column(BigInteger, ForeignKey("teller.account_balances_links.account_balances_links_id"))
    account: Mapped["TellerAccount"] = relationship(
        "TellerAccount",
        primaryjoin="TellerAccountBalances.account_id == TellerAccount.id",
        foreign_keys="[TellerAccountBalances.account_id]",
        back_populates="balances",
        uselist=False
    )
