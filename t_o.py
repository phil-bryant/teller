#! /usr/bin/env python3
from t_c_type import APIClient
from multipledispatch import dispatch

class MyObject():
    _path: str = ""
    _api_client: APIClient = None

    @dispatch(APIClient)
    def __init__(self, api_client: APIClient):
        self.__class__._api_client = api_client

    @dispatch(list)
    def __init__(self, api_data: list):
        self._api_data = api_data

    @dispatch(APIClient, list)
    def __init__(self, api_client: APIClient, api_data: list):
        self.__class__._api_client = api_client
        self._api_data = api_data

    def get_api_data(self):
        return getattr(self, "_api_data", "")

    def __str__(self):
        return f"{super().__str__()}: _path = {self._path}; _api_client = {self._api_client}; _api_data = {self.get_api_data()}"
