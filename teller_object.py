#! /usr/bin/env python3
from teller_object_type import TellerObject
from teller_meta_object import TellerMetaObject
from teller_api_client_type import TellerAPIClientType, APIDataType, APIDataValueType
from iso_date import ISODate
from typing import Optional
from teller_object_field import TellerObjectField

class TellerObject(metaclass=TellerMetaObject): ## https://teller.io/docs/api
    _path: str = ""
    
    def __init__(self, api_data: dict | str):
        self._api_data = api_data
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
            field._parent = self
        else:
            existing_field.value = api_data
            field = existing_field
        ## Also provide direct access to the attribute. In other words,
        ## the line below makes the following eval to True: (self.attrname is self._fields["attrname"].value)
        super().__setattr__(field.name, field.value)

    def _api_client_get(self) -> dict:
        return None if not self._api_client else self._api_client.get(self._path, None)

    def _get_api_data(self):
        api_data = getattr(self, '_api_data', None)
        if api_data is None: self._api_data = self._api_client_get()
        return api_data
    
    def _table_name(self) -> str:
        return self.__module__.replace("teller_", "")

    def is_primary_key(self, field_name: str) -> bool:
        return self._db_client.is_primary_key(self._table_name(), field_name)

    def primary_key(self) -> TellerObjectField:
        return next((field for field in self._fields.values() if field.is_primary_key()), None)

    def db_value(self) -> str:
        return self.primary_key().db_value()

    def save(self) -> TellerObject:
        has_values = any(field.value is not None for field in self._fields.values())
        if has_values:
            for field in self._fields.values(): 
                field.save()
            column_data = {}
            for field in self._fields.values():
                field_value = field.db_value()
                if field_value is not None:
                    column_data[field.db_column_name()] = field_value
            result = self._db_client.upsert(self._table_name(), column_data)
            if result and len(result) > 0:
                for field_name, field_value in result[0].items():
                    if field_name in self._fields:
                        field = self._fields[field_name]
                        typed_value = field_value
                        if field.type_ is int and field_value is not None:
                            typed_value = int(field_value)
                        field.value = typed_value
                        super().__setattr__(field_name, typed_value)
        return self