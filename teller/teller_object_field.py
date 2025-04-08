from .utils.iso_date import ISODate
from .api_client_type import TellerAPIClient
from typing import Optional, Any, Dict
from decimal import Decimal
from enum import Enum
from datetime import date
from collections.abc import Iterable
from .enums import TellerEnum
from dataclasses import dataclass
from psycopg import Connection

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
    
    def is_primary_key(self) -> bool:
        return self._parent.is_primary_key(self.db_column_name())
    
    def is_primitive(self) -> bool:
        return self.type_ in {str, int, Decimal, bool}

    def primitive_db_value(self) -> str:
        return f"'{self.value}'" if isinstance(self.value, str) else str(self.value)
    
    def is_iterable(self) -> bool:
        return isinstance(self.value, Iterable) and not isinstance(self.value, (str, bytes))
    
    def db_column_name(self) -> str:
        return self.metadata.get("db_name", self.name)
    
    def db_value(self) -> Optional[str]:
        result = None
        if self.value is not None and self._parent.has_table_column(self.db_column_name()):
            if self.is_primitive(): result = self.primitive_db_value()
            elif self.is_iterable(): result = ", ".join([item.db_value() for item in self.value])
            else: result = self.value.db_value()
        return result
    
    def save(self):
        if self.is_iterable():
            for each in self.value: each.save()
        else:
            print("DEBUG: teller_object_field.save()")
            if not self.is_primitive() and self.value is not None: self.value.save()
