from teller_object import TellerObject
from teller_enums import TellerTransactionDetailsCounterpartyType

class TellerTransactionDetailsCounterparty(TellerObject): ## https://teller.io/docs/api/account/transactions

    def __init__(self, api_data: dict):
        super().__init__()
        self._set_field("name", str, api_data, {}, )
        self._set_field("type", TellerTransactionDetailsCounterpartyType, api_data, {"enum": True}, )
        self._set_field("transaction_details_counterparty_id", int, api_data, {"pk": True}, )
