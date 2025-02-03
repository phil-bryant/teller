
class TellerList(list):
    def __class_getitem__(cls, item):
        class SubTellerList(cls):
            __orig_type__ = item
            def __init__(self, data=None):
                super(SubTellerList, self).__init__([self.__orig_type__(x) for x in data])
        return SubTellerList