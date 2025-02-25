from teller_object import TellerObject

class TellerIdentityEmail(TellerObject): ## Defined on the Identity page: https://teller.io/docs/api/identity

    def __init__(self, api_data: dict):
        super().__init__()
        self._set_field("data", str, api_data, {}, )
        self._set_field("identity_email_id", int, api_data, {"pk": True}, )
        self._set_field("identity_id", int, api_data, {"fk": True}, )
