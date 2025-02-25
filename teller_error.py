
from teller_object import TellerObject

class TellerError(TellerObject):
    code: Annotation[str, {}] = ""
    message: Annotation[str, {}] = "" 

    def __init__(self, api_data: dict):
        super().__init__()
