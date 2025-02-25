from teller_object import TellerObject

class TellerTransactionType(TellerObject):

    def __init__(self, api_data: dict):
        super().__init__()
        self._set_field("code", str, api_data, {"__str__": True}, )
        self._set_field("transaction_type_id", int, api_data, {"pk": True}, )
