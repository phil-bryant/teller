from typing import Any, Dict
from api_object_field import APIObjectField
from requests import Response

class APIObject:
    def __init__(self, response: Response):
        self._fields: Dict[str, APIObjectField] = {}
 