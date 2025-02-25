from teller_object import TellerObject
from teller_identity_address_data import TellerIdentityAddressData

class TellerIdentityAddress(TellerObject): ## Defined on the Identity page: https://teller.io/docs/api/identity 
    def __init__(self, api_data: dict):
        super().__init__()
        self._set_field("primary", bool, api_data)
        self._set_field("data", TellerIdentityAddressData, api_data, {"fk": True})
        self._set_field("identity_address_id", int, None, {"pk": True})
        self._set_field("identity_id", int, None, {"fk": True})