from dataclasses import dataclass
from sqlalchemy import String, BigInteger, Enum
from sqlalchemy.orm import Mapped, mapped_column
from .teller_object import TellerObject
from .teller_enums import TellerTransactionDetailsCounterpartyType

@dataclass
class TellerTransactionDetailsCounterparty(TellerObject): ## https://teller.io/docs/api/account/transactions
    name: Mapped[str] = mapped_column(String)
    type: Mapped[TellerTransactionDetailsCounterpartyType] = mapped_column(Enum(TellerTransactionDetailsCounterpartyType))
    transaction_details_counterparty_id: Mapped[int] = mapped_column(BigInteger, primary_key=True)