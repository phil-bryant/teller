from teller_object import TellerObject

## Physical address data associated with an Address
## This design allows multiple people to share an address independent of primary designation
## Defined on the Identity page: https://teller.io/docs/api/identity
class TellerIdentityAddressData(TellerObject):
    def __init__(self, api_data):
        super().__init__()
        self._set_field("currency", str, api_data, {})
        self._set_field("street", str, api_data, {})
        self._set_field("city", str, api_data, {})
        self._set_field("region", str, api_data, {})
        self._set_field("postal_code", str, api_data, {})
        self._set_field("country", str, api_data, {})
        self._set_field("identity_address_data_id", int, api_data, {"pk": True})