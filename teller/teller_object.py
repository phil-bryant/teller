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
        ## Convert CamelCase to snake_case
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
    
    def upserted(self, db_result: dict) -> None:
        print(f"\n{self.__class__.__name__} Fields vs DB Results:")
        print(f"{'Object Field':<20} {'Object Value':<25} | {'DB Column':<20} {'DB Value':<25}")
        print(f"{'-'*20:<20} {'-'*25:<25} | {'-'*20:<20} {'-'*25:<25}")
        for field_name, field in self._fields.items():
            db_column = field.db_column_name() if hasattr(field, 'db_column_name') else field_name
            # Display values
            db_value = db_result.get(db_column, None)
            obj_value = field.db_value()   
            obj_value_str = str(obj_value).strip("'\"") if obj_value is not None else 'None'
            db_value_str = str(db_value) if db_value is not None else 'None'
            print(f"{field_name:<20} {obj_value_str[:25]:<25} | {db_column:<20} {db_value_str[:25]:<25}")
            # Check if values changed
            if obj_value_str != 'None' and db_value_str != obj_value_str:
                print(f"DEBUG: Value comparison for field '{field_name}':")
                print(f"  - Object value: type={type(obj_value)}, repr={repr(obj_value)}")
                print(f"  - DB value: type={type(db_value)}, repr={repr(db_value)}")
                
                # More intelligent comparison based on types
                should_raise = True
                
                # Handle numeric types with possible precision differences
                if (isinstance(obj_value, (int, float)) and isinstance(db_value, (int, float))):
                    try:
                        if abs(float(obj_value) - float(db_value)) < 0.00001:
                            should_raise = False
                    except (ValueError, TypeError):
                        pass
                
                # Handle date/time objects with possible format differences
                elif (isinstance(obj_value, datetime) or isinstance(db_value, datetime)):
                    try:
                        # Try to convert both to ISO format for comparison
                        obj_iso = obj_value.isoformat() if isinstance(obj_value, datetime) else obj_value
                        db_iso = db_value.isoformat() if isinstance(db_value, datetime) else db_value
                        if str(obj_iso) == str(db_iso):
                            should_raise = False
                    except (ValueError, TypeError, AttributeError):
                        pass
                
                if should_raise:
                    raise Exception(f"Value mismatch for field '{field_name}': Object value '{obj_value_str}' != DB value '{db_value_str}'")
            # Update None -> value
            if obj_value is None and db_value is not None:
                field.update_value(db_value)

    def save(self) -> TellerObject:
        print()
        print(f"DEBUG: [TellerObject] {self.__class__.__name__}.save(): {self}")
        has_values = any(field.value is not None for field in self._fields.values())
        if has_values:
            with self._db_client.transaction():
                for field in self._fields.values():
                    connection_status = Connection.TransactionStatus(self._db_client._connection.pgconn.transaction_status).name
                    field.save()
                column_data = {}
                for field in self._fields.values():
                    if field.db_value() is not None: column_data[field.db_column_name()] = field.db_value()
                table_name = self._table_name()
                self.upserted(self._db_client.upsert(self._table_schema(), table_name, column_data))
        return self