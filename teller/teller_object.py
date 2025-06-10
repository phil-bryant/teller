#! /usr/bin/env python3
from .object_type import TellerObject
from .teller_meta_object import TellerMetaObject
from .api_client_type import TellerAPIClientType, APIDataType, APIDataValueType
from .utils.iso_date import ISODate
from typing import Optional
from .teller_object_field import TellerObjectField
from psycopg import Connection
import re
from datetime import datetime

class TellerObject(metaclass=TellerMetaObject): ## https://teller.io/docs/api
    _path: str = ""
    
    def __init__(self, api_data: dict | str):
        self._api_data = api_data
        self._fields = {}
        self._set_field("created_at", datetime, None, {"db_ro": True})
        self._set_field("updated_at", datetime, None, {"db_ro": True})

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
    
    def _table_schema(self) -> str:
        return self.__class__.__module__.split('.')[0]

    def _table_name(self) -> str:
        class_name = self.__class__.__name__
        prefix = "Teller"
        if class_name.startswith(prefix):
            class_name = class_name[len(prefix):]
        s1 = re.sub('(.)([A-Z][a-z]+)', r'\1_\2', class_name)
        return re.sub('([a-z0-9])([A-Z])', r'\1_\2', s1).lower()

    def is_primary_key(self, field_name: str) -> bool:
        return self._db_client.is_primary_key(self._table_schema(), self._table_name(), field_name)

    def primary_key(self) -> TellerObjectField:
        return next((field for field in self._fields.values() if field.is_primary_key()), None)

    def db_value(self) -> str:
        return self.primary_key().db_value()
    
    def has_table_column(self, column_name: str) -> bool:
        return self._db_client.has_table_column(self._table_schema(), self._table_name(), column_name)
    
    def constrains(self, aTellerObject) -> bool:
        return self._db_client.constrains(self._table_schema(), self._table_name(), aTellerObject._table_schema(), aTellerObject._table_name())
    
    def upserted(self, db_result: dict) -> None:
        for field_name, field in self._fields.items():
            db_column = field.db_column_name() if hasattr(field, 'db_column_name') else field_name
            db_value = db_result.get(db_column, None)
            obj_value = field.db_value()   
            if obj_value is None and db_value is not None:
                field.update_value(db_value)

    def save(self) -> TellerObject:
        has_values = any(field.value is not None for field in self._fields.values())
        if has_values:
            pass
            with self._db_client.transaction():
                for field in self._fields.values():
                    if not field.constrains(self): field.save()
            with self._db_client.transaction():
                column_data = {}
                for field in self._fields.values():
                    if field.db_value() is not None and not field.constrains(self): 
                        column_data[field.db_column_name()] = field.db_value()
                table_name = self._table_name()                
                if column_data: self.upserted(self._db_client.upsert(self._table_schema(), table_name, column_data))
            with self._db_client.transaction():
                for field in self._fields.values():
                    if field.value is not None and field.constrains(self): field.save()
        return self