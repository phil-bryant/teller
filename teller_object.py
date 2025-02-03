from dataclasses import dataclass, fields
from typing import ClassVar, get_origin, get_args
import structlog

log = structlog.get_logger()

@dataclass
class TellerObject: ## https://teller.io/docs/api
    _api_data: dict
    _api_client: ClassVar[any] = None
    
    @classmethod
    def set_api_client(cls, client):
        cls._api_client = client

    def _mapped_api_data(self):
        ## Handle cases where python objects need field names differing from API field names. See next comment.
        return {field.name: self._api_data[field.metadata.get("api_name", field.name)]
                for field in fields(self.__class__)
                if field.metadata.get("api_name", field.name) in self._api_data}
    
    def _str_field_names(self):
        return [field.name for field in fields(self.__class__) if field.metadata.get("__str__", False)]

    def __post_init__(self):
        ## Use python introspection to otherwise simply mirror the Teller API Objects as python objects.
        log.debug("TellerObject.__post_init__", class_name=self.__class__.__name__, api_data=self._api_data, mapped_api_data=self._mapped_api_data())
        for key, value in self._mapped_api_data().items():
            if hasattr(self, key) and value is not None:
                setattr(self, key, self.__annotations__[key](value)) 

    def __str__(self):
        return f"{self.__class__.__name__}({', '.join(f'{getattr(self, name)}' for name in self._str_field_names())}):_api_data={self._api_data}"