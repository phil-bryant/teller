from .teller_object import TellerObject
from .account import TellerAccount
from .identity import TellerIdentity
from .transaction import TellerTransaction
from typing import Optional

class TellerAccountIdentities(TellerObject): ## https://teller.io/docs/api/identity#get-identity
    _path: str = "/identity"

    def __init__(self, api_data: dict):
        super().__init__(api_data)
        self._set_field("account", TellerAccount, api_data, {"db_table": "account", "fk": True}, self._api_client)
        self._set_field("owners", TellerIdentity, api_data, {"db_table": "identity", "fk": True}, self._api_client)       

    def get_transactions(self, limit: int = 2) -> list[TellerTransaction]:
        return self.account.get_transactions(limit)