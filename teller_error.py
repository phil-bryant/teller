from annotation import Annotation

from teller_object import TellerObject

class TellerError(TellerObject):
    code: Annotation[str, {}] = ""
    message: Annotation[str, {}] = "" 