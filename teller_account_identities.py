from typing import Optional, Any
from teller_object import TellerObject
from field import Field
from teller_account import TellerAccount
from teller_list import TellerList
from teller_identity import TellerIdentity

class TellerAccountIdentities(TellerObject): ## https://teller.io/docs/api/identity#get-identity
    _path: str = "/identity"

    def __init__(self, api_client: Optional[Any] = None, api_data: Optional[dict] = None):
        super().__init__(api_client, api_data)
        self.__setattr__("account", Field(TellerAccount, None, {}))
        self.__setattr__("owners", Field(TellerList[TellerIdentity], None, {"db_table": "identity", "fk": True}))