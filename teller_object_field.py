from plum import dispatch
from teller_api_client_type import TellerAPIClient
from typing import Optional, Any, Dict
from decimal import Decimal
from enum import Enum
from datetime import date
from collections.abc import Iterable
from teller_enum import TellerEnum

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
        return self.type_ in {str, int, Decimal, bool} or issubclass(self.type_, TellerEnum)
    
    def is_iterable(self) -> bool:
        return isinstance(self.value, Iterable) and not isinstance(self.value, (str, bytes))
    
    def db_value(self) -> Optional[str]:
        result = None
        if self.value is not None:
            if self.is_primitive():
                if isinstance(self.value, str):
                    result = "'" + self.value + "'"
                else: 
                    result = str(self.value)
            elif self.is_iterable():
                db_values = [v for v in (each.db_value() for each in self.value if each is not None) if v is not None]
                if db_values:
                    result = ", ".join(db_values)
            elif self.metadata.get("fk", False):
                fk_id_val = None
                for attr_name, attr_value in vars(self.value).items():
                    if attr_name.endswith('_id') and attr_value is not None:
                        fk_id_val = str(attr_value)
                if fk_id_val is not None:
                    result = fk_id_val
            elif hasattr(self.value, 'db_value'):
                result = self.value.db_value()
            
        return result
    
    def db_column_name(self) -> str:
        return self.metadata.get("db_name", self.name)
    
    def save(self):
        if self.is_iterable():
            for each in self.value: each.save()
        elif self.value and not self.is_primitive():
            self.value.save()