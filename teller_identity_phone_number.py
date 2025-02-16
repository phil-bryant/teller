from teller_object import TellerObject
from annotation import Annotation
from teller_enums import TellerIdentityPhoneNumberType

class TellerIdentityPhoneNumber(TellerObject): ## Defined on the Identity page: https://teller.io/docs/api/identity
    type: Annotation[TellerIdentityPhoneNumberType, ({}, )] = None
    data: Annotation[str, ({}, )] = "" 
    identity_phone_number_id: Annotation[int, ({"pk": True}, )] = None
    identity_id: Annotation[int, ({"fk": True}, )] = None