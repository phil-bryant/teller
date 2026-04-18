from dataclasses import dataclass
from sqlalchemy import String, BigInteger
from sqlalchemy.orm import Mapped, mapped_column
from .teller_object import TellerObject

@dataclass
class TellerRoutingNumbers(TellerObject): ## https://teller.io/docs/api/account/details
    ach: Mapped[str] = mapped_column(String, unique=True, nullable=True)
    wire: Mapped[str] = mapped_column(String, unique=True, nullable=True)
    bacs: Mapped[str] = mapped_column(String, nullable=True)
    routing_numbers_id: Mapped[int] = mapped_column(BigInteger, primary_key=True) 