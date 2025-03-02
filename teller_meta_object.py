#! /usr/bin/env python3
from typing import TypeAlias
from plum import dispatch
from teller_api_client_type import TellerAPIClient

APIDataType: TypeAlias = list | dict
APIDataValueType: TypeAlias = dict | str | None

class TellerMetaObject(type):
    _api_client: TellerAPIClient = None

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
        return super().__call__(api_data_value)
    
    @dispatch
    def __call__(cls, api_data_list: list):
        objects = []
        for api_data_item in api_data_list:
            objects.append(cls.__call__(api_data_item))
        return objects