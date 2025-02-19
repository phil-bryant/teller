## This is rather basic functionality that python itself should have implemented
## this allows one to call setattr(variableName, variableValue) in cases where variableName was declared like:
##   names: TellerList[TellerIdentityName] = field(default_factory=list)
## such that names will then be instantiated as a list of TellerIdentityName instances upon calling setattr(...)
class TellerList(list):
    def __class_getitem__(cls, item):
        class SubTellerList(cls):
            __orig_type__ = item
            def __init__(self, data=None):
                super().__init__([
                    self.__orig_type__(api_data=x) if isinstance(x, dict) else x 
                    for x in (data or [])
                ])
        return SubTellerList