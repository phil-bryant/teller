from teller_api_client_type import TellerAPIClient
from teller_object import TellerObject
from field import Field
from teller_account import TellerAccount
from teller_list import TellerList
from teller_identity import TellerIdentity

class TellerAccountIdentities(TellerObject): ## https://teller.io/docs/api/identity#get-identity
    _path: str = "/identity"

    def __init__(self, *args, **kwargs):
        self._set_field("account", TellerAccount, None, {})
        self._set_field("owners", TellerList[TellerIdentity], None, {"db_table": "identity", "fk": True})       
        super().__init__(*args, **kwargs) 