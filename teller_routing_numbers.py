from teller_object import TellerObject

class TellerRoutingNumbers(TellerObject): ## https://teller.io/docs/api/account/details

    def __init__(self, api_data: dict):
        super().__init__()
        self._set_field("ach", str, api_data)
        self._set_field("wire", str, api_data)
        self._set_field("bacs", str, api_data)
        self._set_field("routing_numbers_id", int, None, {"pk": True})
