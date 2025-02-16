from __future__ import annotations
from annotation import Annotation
from typing import Optional, TYPE_CHECKING
if TYPE_CHECKING:
    from teller_api_client import TellerAPIClient
from iso_date import ISODate

class TellerObject: ## https://teller.io/docs/api
    _api_client: Annotation[TellerAPIClient, ({"db": False}, )] = None
    _api_data: Annotation[dict, ({"db": False}, )] = {}
    created_at: Annotation[ISODate, ({"__str__": True}, )] = None
    updated_at: Annotation[ISODate, ({"__str__": True}, )] = None
    
    def __init__(self, api_client: Optional[TellerAPIClient] = None, api_data: Optional[dict] = None):
        self._api_client = api_client
        self._initialize(api_data)
    
    def __str__(self):
        return f"{self.__class__.__name__}({', '.join(f'{getattr(self, name)}' for name in self._str_field_names())}):_api_data={self._api_data}"
    
    def _initialize(self, api_data: dict):
        self._api_data = api_data
        for annotation in self.__annotations__:
            print(annotation)
