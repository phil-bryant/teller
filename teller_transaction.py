from teller_object import TellerObject
from annotation import Annotation
from decimal import Decimal
from iso_date import ISODate
from teller_transaction_details import TellerTransactionDetails
from teller_transaction_links import TellerTransactionLinks
from teller_transaction_type import TellerTransactionType

class TellerTransaction(TellerObject): ## https://teller.io/docs/api/account/transactions
    account_id: Annotation[str, ({}, )] = ""
    amount: Annotation[Decimal, ({"__str__": True}, )] = Decimal('0.00')
    transaction_date: Annotation[ISODate, ({"api_name": "date", "__str__": True}, )] = None
    description: Annotation[str, ({"__str__": True}, )] = ""
    details: Annotation[TellerTransactionDetails, ({"fk": True}, )] = None
    status: Annotation[str, ({"__str__": True}, )] = ""
    id: Annotation[str, ({"pk": True, "db_name": "transaction_id"}, )] = ""
    links: Annotation[TellerTransactionLinks, ({"fk": True}, )] = None
    running_balance: Annotation[str, ({}, )] = ""
    type: Annotation[TellerTransactionType, ({"fk": True}, )] = None