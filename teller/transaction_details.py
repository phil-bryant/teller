from .teller_object import TellerObject
from .enums import TellerTransactionDetailsCategory
from .transaction_details_counterparty import TellerTransactionDetailsCounterparty
from typing import Optional

class TellerTransactionDetails(TellerObject): ## https://teller.io/docs/api/account/transactions
    def __init__(self, api_data: dict):
        super().__init__(api_data)
        self._set_field("processing_status", str, api_data, {"enum": True})
        self._set_field("category", TellerTransactionDetailsCategory, api_data, {"enum": True})
        self._set_field("counterparty", TellerTransactionDetailsCounterparty, api_data, {"fk": True, "db_name": "transaction_details_counterparty_id"})
        self._set_field("transaction_details_id", int, None, {"pk": True})