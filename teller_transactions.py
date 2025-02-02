from dataclasses import dataclass, field
from teller_object import TellerObject
from teller_transactions_details import TellerTransactionsDetails
from teller_transactions_links import TellerTransactionsLinks

## Generated from https://teller.io/docs/api/account/transactions
@dataclass
class TellerTransactions(TellerObject):
    account_id: str = field(default="")
    amount: str = field(default="")
    date: str = field(default="")
    description: str = field(default="")
    details: TellerTransactionsDetails = field(default=None)
    status: str = field(default="")
    id: str = field(default="")
    links: TellerTransactionsLinks = field(default=None)
    running_balance: str = field(default="")
    type: str = field(default="")

    def __str__(self):
        return f"{self.type} {self.status} {self.amount} {self.description}" 