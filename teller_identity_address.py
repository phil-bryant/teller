from teller_object import TellerObject
from annotation import Annotation
from teller_identity_address_data import TellerIdentityAddressData

class TellerIdentityAddress(TellerObject): ## Defined on the Identity page: https://teller.io/docs/api/identity 
    primary: Annotation[bool, ({}, )] = False
    data: Annotation[TellerIdentityAddressData, ({"fk": True}, )] = None
    identity_address_id: Annotation[int, ({"pk": True}, )] = None
    identity_id: Annotation[int, ({"fk": True}, )] = None