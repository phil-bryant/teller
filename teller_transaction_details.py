from dataclasses import dataclass, field
from teller_object import TellerObject
from teller_enums import TellerTransactionCategory
from teller_counterparty import TellerCounterparty

@dataclass
class TellerTransactionDetails(TellerObject):
    category: TellerTransactionCategory = field(default=None)
    processing_status: str = field(default="")
    merchant_name: str = field(default="")
    merchant_website: str = field(default="")
    check_number: str = field(default="")
    type: str = field(default="")
    counterparty: TellerCounterparty = field(default=None) 