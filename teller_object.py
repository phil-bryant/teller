#! /usr/bin/env python3
from teller_meta_object import TellerMetaObject
from field import Field
from iso_date import ISODate
from typing import Any

class TellerObject(metaclass=TellerMetaObject): ## https://teller.io/docs/api
    _path: str = ""
    _api_client = None

    def _set_field(self, name: str, type_: type, api_data: dict, metadata: dict = {}):
        ## Refactor this later
        field = Field(name, type_, api_data[metadata["api_name"] if "api_name" in metadata else name] if api_data else None, metadata)
        self._fields[field.name] = field
        self.__setattr__(field.name, field.value)
        if field.api_name: self.__setattr__("_" + field.api_name, field.value)

    def __init__(self):
        self._fields = {}
        self._set_field("created_at", ISODate, None, {"db_ro": True})
        self._set_field("updated_at", ISODate, None, {"db_ro": True})

    def _get_api_data(self):
        api_data = getattr(self, '_api_data', None)
        if api_data is None: self._api_data = self.api_client_get()
        return api_data
    
    def api_client_get(self) -> dict:
        return None if not self._api_client else self._api_client.get(self._path, None)