from .teller_object import TellerObject
from .utils.iso_date import ISODate
from .enums import TellerIdentityType
from .identity_name import TellerIdentityName
from .identity_address import TellerIdentityAddress
from .identity_phone_number import TellerIdentityPhoneNumber
from .identity_email import TellerIdentityEmail
from typing import Optional, Any

class TellerIdentity(TellerObject): ## https://teller.io/docs/api/identity
    def __init__(self, api_data: dict):
        super().__init__(api_data)
        self._set_field("type", TellerIdentityType, api_data, {"enum": True})
        self._set_field("names", TellerIdentityName, api_data)
        self._set_field("addresses", TellerIdentityAddress, api_data)
        self._set_field("phone_numbers", TellerIdentityPhoneNumber, api_data)
        self._set_field("emails", TellerIdentityEmail, api_data)
        self._set_field("identity_id", int, None, {"pk": True})