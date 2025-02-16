from teller_object import TellerObject
from annotation import Annotation
from teller_enums import TellerTransactionDetailsCounterpartyType

class TellerTransactionDetailsCounterparty(TellerObject): ## https://teller.io/docs/api/account/transactions
    name: Annotation[str, ({}, )] = ""
    type: Annotation[TellerTransactionDetailsCounterpartyType, ({"enum": True}, )] = None
    transaction_details_counterparty_id: Annotation[int, ({"pk": True}, )] = None