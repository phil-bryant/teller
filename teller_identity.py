from typing import List
from teller_object import TellerObject
from annotation import Annotation
from teller_list import TellerList
from teller_enums import TellerIdentityType
from teller_identity_name import TellerIdentityName
from teller_identity_address import TellerIdentityAddress
from teller_identity_phone_number import TellerIdentityPhoneNumber
from teller_identity_email import TellerIdentityEmail

class TellerIdentity(TellerObject): ## https://teller.io/docs/api/identity
    type: Annotation[TellerIdentityType, ({"enum": True}, )] = None
    names: Annotation[List[TellerIdentityName], ({}, )] = []
    addresses: Annotation[List[TellerIdentityAddress], ({}, )] = []
    phone_numbers: Annotation[List[TellerIdentityPhoneNumber], ({}, )] = []
    emails: Annotation[List[TellerIdentityEmail], ({}, )] = []
    identity_id: Annotation[int, ({"pk": True}, )] = None