from dataclasses import dataclass
from sqlalchemy import String, BigInteger, ForeignKey, Enum
from sqlalchemy.orm import Mapped, mapped_column, relationship
from .teller_object import TellerObject
from .teller_enums import TellerTransactionDetailsCategory, TellerTransactionDetailsProcessingStatus
from .teller_transaction_details_counterparty import TellerTransactionDetailsCounterparty

@dataclass
class TellerTransactionDetails(TellerObject): ## https://teller.io/docs/api/account/transactions
    processing_status: Mapped[TellerTransactionDetailsProcessingStatus] = mapped_column(String)
    category: Mapped[TellerTransactionDetailsCategory] = mapped_column(Enum(TellerTransactionDetailsCategory), nullable=True)
    transaction_details_counterparty_id: Mapped[int] = mapped_column(BigInteger, ForeignKey("teller.transaction_details_counterparty.transaction_details_counterparty_id"), nullable=True)
    transaction_details_id: Mapped[int] = mapped_column(BigInteger, primary_key=True)
    counterparty: Mapped[TellerTransactionDetailsCounterparty] = relationship() 