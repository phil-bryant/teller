from teller_object import TellerObject
from annotation import Annotation

class TellerInstitution(TellerObject): ## https://teller.io/docs/api/institutions
    institution_id: Annotation[str, ({"pk": True}, )] = ""
    name: Annotation[str, ({}, )] = "" 