from typing import Optional, Any
from teller_object import TellerObject
from annotation import Annotation

class TellerInstitution(TellerObject): ## https://teller.io/docs/api/institutions
    def __init__(self, api_data: dict):
        super().__init__()
        self._set_field("institution_id", str, api_data, {"pk": True, "api_name": "id"})
        self._set_field("name", str, api_data, {})