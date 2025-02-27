#! /usr/bin/env python3
from plum import dispatch
from teller_api_client_type import TellerAPIClient

class TellerMetaObject(type):
    #@dispatch
    #def __call__(cls, *args, **kwargs):
    #    return super().__call__()

    @dispatch
    def __call__(cls, api_client: None):
        return super().__call__(None)

    @dispatch
    def __call__(cls, api_client: TellerAPIClient):
        cls._api_client = api_client
        return cls.__call__(cls._api_client.get(cls._path))
    
    @dispatch
    def __call__(cls, api_data_str: str):
        return super().__call__(api_data_str)

    @dispatch
    def __call__(cls, api_data: dict):
        return super().__call__(api_data)

    @dispatch
    def __call__(cls, api_data: dict, api_client: TellerAPIClient):
        cls._api_client = api_client
        return cls.__call__(api_data)
    
    @dispatch
    def __call__(cls, api_data_list: list, api_client: TellerAPIClient):
        cls._api_client = api_client
        return cls.__call__(api_data_list)

    @dispatch
    def __call__(cls, api_data_list: list):
        objects = []
        for api_data_item in api_data_list:
            objects.append(cls.__call__(api_data_item))
        return objects

