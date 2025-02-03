from dataclasses import dataclass, field
from teller_object import TellerObject
from teller_enums import TellerTransactionDetailsCategory
from teller_transaction_details_counterparty import TellerTransactionDetailsCounterparty

@dataclass
class TellerTransactionDetails(TellerObject): ## https://teller.io/docs/api/account/transactions
    processing_status: str = field(default="")
    category: TellerTransactionDetailsCategory = field(default=None)
    counterparty: TellerTransactionDetailsCounterparty = field(default=None) 