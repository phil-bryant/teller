#! /usr/bin/env python3
from typing import TypeAlias
from plum import dispatch
from teller_api_client_type import TellerAPIClient, APIDataType, APIDataValueType
from teller_db_client import TellerDBClient

class TellerMetaObject(type):
    _api_client: TellerAPIClient = None
    _db_client: TellerDBClient = None
    @dispatch
    def __call__(cls, api_client: TellerAPIClient):
        cls._api_client = api_client
        return cls.__call__(cls._api_client.get(cls._path))
    
    @dispatch
    def __call__(cls, api_data: APIDataType, api_client: TellerAPIClient):
        cls._api_client = api_client
        return cls.__call__(api_data)
    
    @dispatch
    def __call__(cls, api_data_value: APIDataValueType):
        ## NB in a metaclass __call__(...) intercepts object construction prior to __new__
        ## perhaps because python was named after the absurdist comedy Monty Python's Flying Circus,
        ## here super() actually refers to the subclass-of-the-subclass of the metaclass
        return super().__call__(api_data_value)
    
    @dispatch
    def __call__(cls, api_data_list: list):
        objects = []
        for api_data_item in api_data_list:
            objects.append(cls.__call__(api_data_item))
        return objects
    
    def __init__(cls, name, bases, attrs):
        super().__init__(name, bases, attrs)
        cls._db_client = TellerDBClient()
