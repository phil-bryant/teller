from teller_object import TellerObject
from annotation import Annotation
from teller_enums import TellerTransactionDetailsCategory
from teller_transaction_details_counterparty import TellerTransactionDetailsCounterparty

class TellerTransactionDetails(TellerObject): ## https://teller.io/docs/api/account/transactions
    processing_status: Annotation[str, ({"enum": True}, )] = ""
    category: Annotation[TellerTransactionDetailsCategory, ({"enum": True}, )] = None
    counterparty: Annotation[TellerTransactionDetailsCounterparty, ({"fk": True}, )] = None 
    transaction_details_id: Annotation[int, ({"pk": True}, )] = None