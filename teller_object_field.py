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
        result = ""
        if self.value is not None:
            if self.is_primitive():
                if isinstance(self.value, str):
                    result = "'" + self.value + "'"
                else:
                    result = str(self.value)
            elif self.is_iterable(): result = ", ".join(each.db_value() for each in self.value)
            elif hasattr(self.value, 'db_value'): result = self.value.db_value()
        return result
    
    def db_column_name(self) -> str:
        return self.metadata.get("db_name", self.name)
    
    def save(self):
        if self.is_iterable():
            for each in self.value: each.save()
        elif self.value and not self.is_primitive():
            self.value.save()