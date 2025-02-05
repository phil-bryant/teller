from dataclasses import dataclass
from sqlalchemy import String, BigInteger, ForeignKey, Numeric, Date, Enum
from sqlalchemy.orm import Mapped, mapped_column, relationship
from teller_object import TellerObject
from teller_transaction_details import TellerTransactionDetails
from teller_transaction_links import TellerTransactionLinks
from teller_transaction_type import TellerTransactionType
from teller_enums import TellerTransactionStatus

@dataclass
class TellerTransaction(TellerObject): ## https://teller.io/docs/api/account/transactions
    account_id: Mapped[str] = mapped_column(String, ForeignKey("teller.account.account_id"))
    amount: Mapped[float] = mapped_column(Numeric(15,2))
    date: Mapped[Date] = mapped_column(Date)
    description: Mapped[str] = mapped_column(String)
    transaction_details_id: Mapped[int] = mapped_column(BigInteger, ForeignKey("teller.transaction_details.transaction_details_id"), unique=True)
    status: Mapped[TellerTransactionStatus] = mapped_column(Enum(TellerTransactionStatus))
    transaction_id: Mapped[str] = mapped_column(String, primary_key=True)
    transaction_links_id: Mapped[int] = mapped_column(BigInteger, ForeignKey("teller.transaction_links.transaction_links_id"), unique=True)
    running_balance: Mapped[float] = mapped_column(Numeric(15,2), nullable=True)
    transaction_type_id: Mapped[int] = mapped_column(BigInteger, ForeignKey("teller.transaction_type.transaction_type_id"))
    details: Mapped[TellerTransactionDetails] = relationship()
    links: Mapped[TellerTransactionLinks] = relationship()
    type: Mapped[TellerTransactionType] = relationship()