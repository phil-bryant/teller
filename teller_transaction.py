from dataclasses import dataclass, field
from decimal import Decimal
from iso_date import ISODate
from teller_object import TellerObject
from teller_transaction_details import TellerTransactionDetails
from teller_transaction_links import TellerTransactionLinks
from teller_transaction_type import TellerTransactionType

@dataclass
class TellerTransaction(TellerObject): ## https://teller.io/docs/api/account/transactions
    account_id: str = field(default="")
    amount: Decimal = field(default_factory=lambda: Decimal('0.00'), metadata={"__str__": True})
    transaction_date: ISODate = field(default=None, metadata={"api_name": "date", "__str__": True})
    description: str = field(default="", metadata={"__str__": True})
    details: TellerTransactionDetails = field(default=None)
    status: str = field(default="", metadata={"__str__": True})
    id: str = field(default="")
    links: TellerTransactionLinks = field(default=None)
    running_balance: str = field(default="")
    type: TellerTransactionType = field(default=None)