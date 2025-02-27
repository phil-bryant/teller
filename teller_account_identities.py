from teller_object import TellerObject
from teller_account import TellerAccount
from teller_identity import TellerIdentity
from teller_transaction import TellerTransaction

class TellerAccountIdentities(TellerObject): ## https://teller.io/docs/api/identity#get-identity
    _path: str = "/identity"

    def __init__(self, api_data: dict):
        super().__init__()
        self._set_field("account", TellerAccount, api_data, {"db_table": "account", "fk": True}, self._api_client)
        self._set_field("owners", TellerIdentity, api_data, {"db_table": "identity", "fk": True}, self._api_client)       

    def get_transactions(self, limit: int = 2) -> list[TellerTransaction]:
        return self.account.get_transactions(limit)