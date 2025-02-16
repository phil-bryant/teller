from typing import List
from teller_object import TellerObject
from annotation import Annotation
from teller_account import TellerAccount
from teller_identity import TellerIdentity

class TellerAccountIdentities(TellerObject): ## https://teller.io/docs/api/identity#get-identity
    account: Annotation[TellerAccount, ({}, )] = None
    owners: Annotation[List[TellerIdentity], ({"db_table": "identity", "fk": True}, )] = None