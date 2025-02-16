from decimal import Decimal
from teller_object import TellerObject
from annotation import Annotation
from teller_account_balances_links import TellerAccountBalancesLinks

class TellerAccountBalances(TellerObject):
    account_id: Annotation[str, ({"fk": True}, )] = ""
    ledger: Annotation[Decimal, ({"__str__": True}, )] = Decimal('0.00')
    available: Annotation[Decimal, ({"__str__": True}, )] = Decimal('0.00')
    links: Annotation[TellerAccountBalancesLinks, {}] = None
    account_balances_id: Annotation[int, ({"pk": True}, )] = None

    def __init__(self, api_data: dict):
        super().__init__(api_data)