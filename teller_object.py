#! /usr/bin/env python3
from teller_meta_object import TellerMetaObject
from field import Field
from iso_date import ISODate
from typing import Any

class TellerObject(metaclass=TellerMetaObject): ## https://teller.io/docs/api
    _path: str = ""
    _api_client = None

    def _set_field(self, name: str, type_: type, value: Any, metadata: dict):
        field = Field(name, type_, value, metadata)
        self.__setattr__("_" + name, field)
        self.__setattr__(field.name, type_(field.value))
        if field.api_name: self.__setattr__("_" + field.api_name, field.value)

    def __init__(self, api_data: dict):
        self._set_field("created_at", ISODate, None, {"db_ro": True})
        self._set_field("updated_at", ISODate, None, {"db_ro": True})
        for key, value in (api_data or {}).items():
            pass
            self._set_field(key, type(value), value, {})

    def _field_type_(self, name: str):
        return self.__dict__["_" + name].type_

    def _get_api_data(self):
        api_data = getattr(self, '_api_data', None)
        if api_data is None: self._api_data = self.api_client_get()
        return api_data
    
    def fields(self):
        return {k: v for k, v in self.__dict__.items() if isinstance(v, Field)}
    
    def api_client_get(self) -> dict:
        return None if not self._api_client else self._api_client.get(self._path, None)