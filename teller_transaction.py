from dataclasses import dataclass
from sqlalchemy import String, BigInteger, ForeignKey, Numeric, Date, Enum
from sqlalchemy.orm import Mapped, mapped_column, relationship
from teller_object import TellerObject
from teller_transaction_details import TellerTransactionDetails
from teller_transaction_links import TellerTransactionLinks
from teller_transaction_type import TellerTransactionType
from teller_enums import TellerTransactionStatus
from typing import TYPE_CHECKING
if TYPE_CHECKING: from teller_account import TellerAccount

@dataclass
class TellerTransaction(TellerObject): ## https://teller.io/docs/api/account/transactions
    account_id: Mapped[str] = mapped_column(String, ForeignKey("teller.account.account_id"))
    amount: Mapped[float] = mapped_column(Numeric(15,2))
    date: Mapped[Date] = mapped_column(Date)
    description: Mapped[str] = mapped_column(String)
    details: Mapped[TellerTransactionDetails] = relationship()
    status: Mapped[TellerTransactionStatus] = mapped_column(Enum(TellerTransactionStatus))
    id: Mapped[str] = mapped_column(String, primary_key=True)
    links: Mapped[TellerTransactionLinks] = relationship()
    running_balance: Mapped[float] = mapped_column(Numeric(15,2), nullable=True)
    type: Mapped[TellerTransactionType] = relationship()
    transaction_details_id: Mapped[int] = mapped_column(BigInteger, ForeignKey("teller.transaction_details.transaction_details_id"), unique=True)
    transaction_links_id: Mapped[int] = mapped_column(BigInteger, ForeignKey("teller.transaction_links.transaction_links_id"), unique=True)
    transaction_type_id: Mapped[int] = mapped_column(BigInteger, ForeignKey("teller.transaction_type.transaction_type_id"))
    account: Mapped["TellerAccount"] = relationship(
        "TellerAccount",
        primaryjoin="TellerTransaction.account_id == TellerAccount.id",
        foreign_keys="[TellerTransaction.account_id]",
        back_populates="transactions",
        uselist=False
    )