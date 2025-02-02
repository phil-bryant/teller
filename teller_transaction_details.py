from dataclasses import dataclass, field
from teller_object import TellerObject
from teller_enums import TellerTransactionDetailsCategory
from teller_transaction_details_counterparty import TellerTransactionDetailsCounterparty

@dataclass
class TellerTransactionDetails(TellerObject):
    category: TellerTransactionDetailsCategory = field(default=None)
    processing_status: str = field(default="")
    merchant_name: str = field(default="")
    merchant_website: str = field(default="")
    check_number: str = field(default="")
    type: str = field(default="")
    counterparty: TellerTransactionDetailsCounterparty = field(default=None) 