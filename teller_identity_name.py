from teller_object import TellerObject
from teller_enums import TellerIdentityNameType

class TellerIdentityName(TellerObject): ## Defined on the Identity page: https://teller.io/docs/api/identity

    def __init__(self, api_data: dict):
        super().__init__()
        self._set_field("type", TellerIdentityNameType, api_data)
        self._set_field("data", str, api_data)
        self._set_field("identity_name_id", int, None, {"pk": True})
        self._set_field("identity_id", int, None, {"fk": True})
