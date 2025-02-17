from typing import Optional, TypeVar
from teller_object import TellerObject
TellerAPIClientT = TypeVar("TellerAPIClientT")

class TellerAccountIdentities(TellerObject): ## https://teller.io/docs/api/identity#get-identity

    def __init__(self, api_client: Optional[TellerAPIClientT] = None, api_data: Optional[dict] = None):
        super().__init__(api_client, api_data)
        # self.account: Annotation[TellerAccount, ({}, )] = None
        #self.owners: Annotation[List[TellerIdentity], ({"db_table": "identity", "fk": True}, )] = None