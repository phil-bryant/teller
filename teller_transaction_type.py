from teller_object import TellerObject

class TellerTransactionType(TellerObject):
    def __init__(self, api_data_str: str):
        super().__init__(api_data_str)
        self._set_field("code", str, api_data_str, {"__str__": True})
        self._set_field("transaction_type_id", int, None, {"pk": True})
