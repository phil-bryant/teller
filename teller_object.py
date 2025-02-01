from dataclasses import dataclass
from typing import ClassVar, get_origin, get_args
import structlog

log = structlog.get_logger()

@dataclass
class TellerObject:
    _api_data: dict
    _api_client: ClassVar[any] = None
    
    @classmethod
    def set_api_client(cls, client):
        cls._api_client = client
    
    def __init__(self, api_data: dict):
        self._api_data = api_data
        

    def __post_init__(self):
        ## Use python introspection to simply mirror the Teller API Objects as python objects.
        log.debug("TellerObject.__post_init__", class_name=self.__class__.__name__, api_data=self._api_data)
        for key, value in self._api_data.items():
            if hasattr(self, key) and value is not None:
                if get_origin(self.__annotations__[key]) is list:
                    setattr(self, key, [get_args(self.__annotations__[key])[0](element) for element in value])
                else:
                    setattr(self, key, self.__annotations__[key](value)) 