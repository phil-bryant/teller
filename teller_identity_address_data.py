from teller_object import TellerObject
from annotation import Annotation

## Physical address data associated with an Address
## This design allows multiple people to share an address independent of primary designation
## Defined on the Identity page: https://teller.io/docs/api/identity
class TellerIdentityAddressData(TellerObject):
    street: Annotation[str, ({}, )] = ""
    city: Annotation[str, ({}, )] = ""
    region: Annotation[str, ({}, )] = ""
    postal_code: Annotation[str, ({}, )] = ""
    country: Annotation[str, ({}, )] = ""
    identity_address_data_id: Annotation[int, ({"pk": True}, )] = None