from teller_object import TellerObject
from typing import List, Optional, Any
from teller_enums import TellerIdentityType
from teller_identity_name import TellerIdentityName
from teller_identity_address import TellerIdentityAddress
from teller_identity_phone_number import TellerIdentityPhoneNumber
from teller_identity_email import TellerIdentityEmail

class TellerIdentity(TellerObject): ## https://teller.io/docs/api/identity
    def __init__(self, api_data: dict):
        super().__init__()
        self._set_field("type", TellerIdentityType, api_data, {"enum": True})
        self._set_field("names", TellerIdentityName, api_data)
        self._set_field("addresses", TellerIdentityAddress, api_data)
        self._set_field("phone_numbers", TellerIdentityPhoneNumber, api_data)
        self._set_field("emails", TellerIdentityEmail, api_data)
        self._set_field("identity_id", int, None, {"pk": True})