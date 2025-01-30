from dataclasses import dataclass, field
from teller_object import TellerObject
from teller_transaction_details import TellerTransactionDetails
from teller_transaction_counterparty import TellerTransactionCounterparty
from teller_transaction_links import TellerTransactionLinks

@dataclass
class TellerTransaction(TellerObject):
    id: str = field(default="")
    amount: str = field(default="")
    date: str = field(default="")
    description: str = field(default="")
    status: str = field(default="")
    type: str = field(default="")
    account_id: str = field(default="")
    running_balance: str = field(default="")
    details: TellerTransactionDetails = field(default=None)
    counterparty: TellerTransactionCounterparty = field(default=None)
    links: TellerTransactionLinks = field(default=None)

    def __str__(self):
        return f"{self.type} {self.status} {self.amount} {self.description}" 