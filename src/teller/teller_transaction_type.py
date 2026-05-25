from dataclasses import dataclass
from sqlalchemy import String, BigInteger
from sqlalchemy.orm import Mapped, mapped_column
from .teller_object import TellerObject

@dataclass
class TellerTransactionType(TellerObject): ## https://teller.io/docs/api/account/transactions
    code: Mapped[str] = mapped_column(String, unique=True)
    description: Mapped[str] = mapped_column(String)
    transaction_type_id: Mapped[int] = mapped_column(BigInteger, primary_key=True)

    def __init__(self, api_data):
        if isinstance(api_data, str):
            self.code = api_data
            self._api_data = {"code": api_data}
        else:
            super().__init__(api_data)