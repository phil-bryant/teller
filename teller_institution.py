from typing import Optional, Any
from teller_object import TellerObject
from annotation import Annotation

class TellerInstitution(TellerObject): ## https://teller.io/docs/api/institutions
    def __init__(self, api_data: dict):
        super().__init__(api_data)
        self._set_field("institution_id", str, api_data, {"pk": True})
        self._set_field("name", str, api_data, {})