from teller_object import TellerObject
from annotation import Annotation

class TellerTransactionType(TellerObject):
    code: Annotation[str, ({"__str__": True}, )] = ""
    transaction_type_id: Annotation[int, ({"pk": True}, )] = None