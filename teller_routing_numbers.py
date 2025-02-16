from teller_object import TellerObject
from annotation import Annotation

class TellerRoutingNumbers(TellerObject): ## https://teller.io/docs/api/account/details
    ach: Annotation[str, ({}, )] = ""
    wire: Annotation[str, ({}, )] = ""
    bacs: Annotation[str, ({}, )] = "" 
    routing_numbers_id: Annotation[int, ({"pk": True}, )] = None