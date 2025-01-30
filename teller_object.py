from dataclasses import dataclass, is_dataclass
from typing import List, get_origin, get_args, TypeVar, ClassVar

@dataclass
class TellerObject:
    api_data: dict
    api_client: ClassVar[any] = None
    
    @classmethod
    def set_api_client(cls, client):
        cls.api_client = client
    
    def __init__(self, api_data: dict):
        self.api_data = api_data
        
    def __post_init__(self):
        for key, value in self.api_data.items():
            if hasattr(self, key):
                field_type = self.__annotations__[key]
                setattr(self, key, field_type(value)) 