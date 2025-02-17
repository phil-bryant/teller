from field import Field
from typing import Any, Optional
from iso_date import ISODate

class TellerObject: ## https://teller.io/docs/api
    _path: str = ""

    def _set_field(self, name: str, type_: type, value: Any, metadata: dict):
        self.__setattr__("_" + name, Field(type_, value, metadata))
        self.__setattr__(name, value)

    def api_data(self):
        if not self._api_data and self._api_client: 
            self._set_field("_api_data", dict, self._api_client.get(self._path, None), {"db_store": False})
        return self._api_data

    def _initialize(self):
        api_data = self.api_data()
        print(api_data)

    def __init__(self, api_client: Optional[Any] = None, api_data: Optional[dict] = None):
        self._set_field("_api_client", Any, api_client, {"db_store": False})
        self._set_field("_api_data", dict, api_data, {"db_store": False})
        self._set_field("_created_at", ISODate, None, {"db_ro": True})
        self._set_field("_updated_at", ISODate, None, {"db_ro": True})
        self._initialize()
        
    def __str__(self):
        return f"{self.__class__.__name__}({', '.join(f'{getattr(self, name)}' for name in self._str_field_names())}):_api_data={self._api_data}"
