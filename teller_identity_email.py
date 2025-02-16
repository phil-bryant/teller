from teller_object import TellerObject
from annotation import Annotation

class TellerIdentityEmail(TellerObject): ## Defined on the Identity page: https://teller.io/docs/api/identity
    data: Annotation[str, ({}, )] = "" 
    identity_email_id: Annotation[int, ({"pk": True}, )] = None
    identity_id: Annotation[int, ({"fk": True}, )] = None