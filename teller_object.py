#! /usr/bin/env python3
from field import Field
from typing import Any, Optional
from iso_date import ISODate
from dataclasses import dataclass

class TellerObjectMeta(type):
    def __call__(cls, *args, **kwargs):
        return super().__call__(*args, **kwargs).__post_init__()

class TellerObject(metaclass=TellerObjectMeta): ## https://teller.io/docs/api
    _path: str = ""

    def __call__(cls, *args, **kwargs):
        print("TellerObject.__call__")
        super().__call__(*args, **kwargs)
 
    def _set_field(self, name: str, type_: type, value: Any, metadata: dict):
        field = Field(name, type_, value, metadata)
        self.__setattr__("_" + name, field)
        self.__setattr__(field.name, field.value)
        if field.api_name: self.__setattr__("_" + field.api_name, field.value)

    def _field_type_(self, name: str):
        return self.__dict__["_" + name].type_

    def _get_api_data(self):
        return getattr(self, '_api_data', None) or self.api_client_get()
    
    def fields(self):
        return {k: v for k, v in self.__dict__.items() if isinstance(v, Field)}
       
    def __init__(self, api_client: Optional[Any] = None, api_data: Optional[dict] = None):
        self._api_client = api_client
        self._api_data = self._get_api_data() 
        self._set_field("created_at", ISODate, None, {"db_ro": True})
        self._set_field("updated_at", ISODate, None, {"db_ro": True})

    def __post_init__(self):
        api_data = self._get_api_data()
        fields = list(self.fields().values())
        for api_fields in api_data:
            for api_field_name, api_field_value in api_fields.items():
                field = self.fields()["_" + api_field_name]
                setattr(field, "value", field.type_(api_field_value))
        return self
    
    def api_client_get(self) -> dict:
        return None if not self._api_client else self._api_client.get(self._path, None)
        
if __name__ == "__main__":
    from teller_api_client import main
    main() 