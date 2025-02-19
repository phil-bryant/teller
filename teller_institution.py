from typing import Optional, Any
from teller_object import TellerObject
from annotation import Annotation

class TellerInstitution(TellerObject): ## https://teller.io/docs/api/institutions
    def __init__(self, api_client: Optional[Any] = None, api_data: Optional[dict] = None):
        super().__init__(api_client, api_data)
        self._set_field("institution_id", str, api_data, {"pk": True})
        self._set_field("name", str, api_data, {})