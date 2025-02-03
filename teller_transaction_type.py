from dataclasses import dataclass, field
from teller_object import TellerObject

@dataclass
class TellerTransactionType(TellerObject):
    code: str = field(default="")

    def __init__(self, api_data):
        if isinstance(api_data, str):
            self.code = api_data
            self._api_data = {"code": api_data}
        else:
            super().__init__(api_data)

    def __str__(self):
        return self.code