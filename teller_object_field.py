from plum import dispatch
from teller_api_client_type import TellerAPIClient
from typing import Optional, Any, Dict
from decimal import Decimal
from enum import Enum
from datetime import date
from collections.abc import Iterable

class TellerObjectField:

    def __init__(self, name_: str, type_: type, value_: Any, metadata_: Optional[dict] = None, api_client: Optional[TellerAPIClient] = None):
        self.name = name_
        self.type_ = type_
        self.metadata = metadata_ or {}
        api_name = self.metadata.get("api_name", name_)
        value_data = value_[api_name] if api_name in (value_ or {}) else None
        ## NB type_(...) calls the appropriate constructor
        if api_client is None: self.value = type_(value_data) if value_data is not None else None
        else: self.value = type_(value_data, api_client)

    def __repr__(self):
        return f"{self.__class__.__name__}({self.name}: {self.type_.__name__} = {self.value} {self.metadata})" 
    
    def is_db_ro(self) -> bool:
        return self.metadata.get("db_ro", False) ## database read only column; cannot insert it
    
    def is_primary_key(self) -> bool:
        return self.metadata.get("pk", False)
    
    def is_primitive(self) -> bool:
        return self.type_ in {str, int, Decimal, bool} or issubclass(self.type_, Enum)
    
    def is_iterable(self) -> bool:
        return isinstance(self.value, Iterable) and not isinstance(self.value, (str, bytes))
    
    def db_value(self) -> str:
        value_str = ""
        if self.value is None: value_str = ""
        elif self.is_primitive(): value_str = str(self.value)
        elif self.is_iterable(): value_str = ", ".join(each.db_value() for each in self.value)
        else: value_str = self.value.db_value()
        return value_str
    
    def save(self) -> str:
        if self.is_iterable(): 
            for each in self.value: each.save()
        elif not (self.value is None or self.is_primitive()): self.value.save()
        return self.db_value()