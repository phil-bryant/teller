from typing import get_origin
import structlog

log = structlog.get_logger()

class TellerList(list):
    def __class_getitem__(cls, item):
        class SubTellerList(cls):
            __orig_type__ = item
            def __new__(subcls, *a, **b):
                i = super(SubTellerList, subcls).__new__(subcls, *a, **b)
                log.info("Observing TellerList usage", typed_item=subcls.__orig_type__)
                return i
            def __init__(self, data=None):
                conv = []
                if data is None:
                    pass
                elif isinstance(data, dict):
                    conv.append(self.__orig_type__(data))
                else:
                    conv = [self.__orig_type__(x) for x in data]
                super(SubTellerList, self).__init__(conv)
        return SubTellerList