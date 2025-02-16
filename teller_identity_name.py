from teller_object import TellerObject
from teller_enums import TellerIdentityNameType
from annotation import Annotation

class TellerIdentityName(TellerObject): ## Defined on the Identity page: https://teller.io/docs/api/identity
    type: Annotation[TellerIdentityNameType, ({}, )] = None
    data: Annotation[str, ({}, )] = ""
    identity_name_id: Annotation[int, ({"pk": True}, )] = None
    identity_id: Annotation[int, ({"fk": True}, )] = None