from teller_object import TellerObject
from typing import List, Optional, Any
from teller_enums import TellerIdentityType
from teller_list import TellerList
from teller_identity_name import TellerIdentityName
from teller_identity_address import TellerIdentityAddress
from teller_identity_phone_number import TellerIdentityPhoneNumber
from teller_identity_email import TellerIdentityEmail

class TellerIdentity(TellerObject): ## https://teller.io/docs/api/identity

    def __init__(self, api_client: Optional[Any] = None, api_data: Optional[dict] = None):
        super().__init__(api_client, api_data)
        self._set_field("type", TellerIdentityType, api_data, {"enum": True})
        self._set_field("names", TellerList[TellerIdentityName], api_data, {})
        self._set_field("addresses", TellerList[TellerIdentityAddress], api_data, {})
        self._set_field("phone_numbers", TellerList[TellerIdentityPhoneNumber], api_data, {})
        self._set_field("emails", TellerList[TellerIdentityEmail], api_data, {})
        self._set_field("identity_id", int, api_data, {"pk": True})