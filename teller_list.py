from typing import get_origin
import structlog

log = structlog.get_logger()

class TellerList(list):
    __orig_type__=None
    def __class_getitem__(cls,item):
        cls.__orig_type__=item
        log.info("TellerList.__class_getitem__", item=item)
        return cls
    def __new__(cls,*a,**b):
        i=super(TellerList,cls).__new__(cls,*a,**b)
        log.info("Observing TellerList usage at runtime", typed_item=cls.__orig_type__)
        return i