from teller_object import TellerObject
from teller_account import TellerAccount
from teller_identity import TellerIdentity

class TellerAccountIdentities(TellerObject): ## https://teller.io/docs/api/identity#get-identity
    _path: str = "/identity"

    def __init__(self, api_data: dict):
        super().__init__()
        self._set_field("account", TellerAccount, api_data)
        self._set_field("owners", TellerIdentity, api_data, {"db_table": "identity", "fk": True})       
