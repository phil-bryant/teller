from dataclasses import dataclass, field
from teller_object import TellerObject
from teller_transaction_details import TellerTransactionDetails
from teller_transaction_links import TellerTransactionLinks
from teller_transaction_type import TellerTransactionType

@dataclass
class TellerTransaction(TellerObject): ## https://teller.io/docs/api/account/transactions
    account_id: str = field(default="")
    amount: str = field(default="", metadata={"__str__": True})
    date: str = field(default="")
    description: str = field(default="", metadata={"__str__": True})
    details: TellerTransactionDetails = field(default=None)
    status: str = field(default="", metadata={"__str__": True})
    id: str = field(default="")
    links: TellerTransactionLinks = field(default=None)
    running_balance: str = field(default="")
    type: TellerTransactionType = field(default=None)