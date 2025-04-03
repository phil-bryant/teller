#! /usr/bin/env python3
from teller_object import TellerObject
from decimal import Decimal
from iso_date import ISODate
from teller_transaction_details import TellerTransactionDetails
from teller_transaction_links import TellerTransactionLinks
from teller_transaction_type import TellerTransactionType

class TellerTransaction(TellerObject): ## https://teller.io/docs/api/account/transactions
    def __init__(self, api_data: dict):
        super().__init__(api_data)
        print(f"DEBUG: Transaction: {type(api_data)}")
        self._set_field("account_id", str, api_data)
        self._set_field("amount", Decimal, api_data, {"__str__": True})
        self._set_field("transaction_date", ISODate, api_data, {"api_name": "date", "__str__": True})
        self._set_field("description", str, api_data, {"__str__": True})
        self._set_field("details", TellerTransactionDetails, api_data, {"fk": True, "db_name": "transaction_details_id"})
        self._set_field("status", str, api_data, {"__str__": True})
        self._set_field("id", str, api_data, {"pk": True, "db_name": "transaction_id"})
        self._set_field("links", TellerTransactionLinks, api_data, {"fk": True, "db_name": "transaction_links_id"})
        self._set_field("running_balance", str, api_data)
        print(f"DEBUG: about to set type")
        self._set_field("type", TellerTransactionType, api_data, {"fk": True, "db_name": "transaction_type_id"})
        print(f"DEBUG: Field setting complete for transaction {api_data.get('id') if isinstance(api_data, dict) else None}")

    def save(self):
        print(f"DEBUG: Transaction: {self}")
        super().save()
