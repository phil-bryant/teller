from dataclasses import dataclass, field
from teller_object import TellerObject
from teller_transaction_details import TellerTransactionDetails
from teller_transaction_counterparty import TellerTransactionCounterparty
from teller_transaction_links import TellerTransactionLinks

@dataclass
class TellerTransaction(TellerObject):
    account_id: str = field(default="")
    amount: str = field(default="")
    date: str = field(default="")
    description: str = field(default="")
    details: TellerTransactionDetails = field(default=None)
    status: str = field(default="")
    id: str = field(default="")
    links: TellerTransactionLinks = field(default=None)
    running_balance: str = field(default="")
    type: str = field(default="")

    def __str__(self):
        return f"{self.type} {self.status} {self.amount} {self.description}" 