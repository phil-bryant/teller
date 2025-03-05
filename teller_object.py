#! /usr/bin/env python3
from teller_object_type import TellerObject
from teller_meta_object import TellerMetaObject
from teller_api_client_type import TellerAPIClientType, APIDataType, APIDataValueType
from iso_date import ISODate
from typing import Optional
from teller_object_field import TellerObjectField

class TellerObject(metaclass=TellerMetaObject): ## https://teller.io/docs/api
    _path: str = ""
    def __init__(self):
        self._fields = {}
        self._set_field("created_at", ISODate, None, {"db_ro": True})
        self._set_field("updated_at", ISODate, None, {"db_ro": True})

    ## Store our public attributes in a dict of TellerObjectField instances
    def __setattr__(self, name: str, value: object) -> None:
        if name.startswith('_'): super().__setattr__(name, value)
        else: self._set_field(name, type(value), value)

    def _get_field(self, name: str) -> TellerObjectField:
        return self._fields.get(name, None)

    def _set_field(self, name: str, type_: type, api_data, metadata: APIDataValueType = None, api_client: TellerAPIClientType = None):
        existing_field = self._get_field(name)
        if existing_field is None:
            field = TellerObjectField(name, type_, api_data, metadata, api_client)
            self._fields[field.name] = field
        else:
            existing_field.value = api_data
            field = existing_field
        ## The line below makes the following: (self.attrname is self._fields["attrname"].value) == True
        super().__setattr__(field.name, field.value)

    def _api_client_get(self) -> dict:
        return None if not self._api_client else self._api_client.get(self._path, None)

    def _get_api_data(self):
        api_data = getattr(self, '_api_data', None)
        if api_data is None: self._api_data = self._api_client_get()
        return api_data
    
    def _table_name(self) -> str:
        return self.__module__.replace("teller_", "")
    
    def primary_key(self) -> str:
        return next((fv.db_value() for fv in self._fields.values() if fv.is_primary_key()), None)
    
    def db_value(self) -> str:
        return self.primary_key()

    def save(self) -> TellerObject:
        column_data = {}
        for field_name, field in self._fields.items():
            field.save()
            if not field.is_db_ro(): column_data[field_name] = field.db_value()
        return self._db_client.insert(self._table_name(), column_data)
