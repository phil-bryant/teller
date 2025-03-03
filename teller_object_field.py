from plum import dispatch
from teller_api_client_type import TellerAPIClient
from typing import Optional, Any, Dict

class TellerObjectField:

    def __init__(self, name_: str, type_: type, value_: Any, metadata_: Optional[dict] = None, api_client: Optional[TellerAPIClient] = None):
        self.name = name_
        self.type_ = type_
        self.metadata = metadata_ or {}
        api_name = self.metadata.get("api_name", name_)
        value_data = value_[api_name] if api_name in (value_ or {}) else None
        ## NB type_(...) calls the appropriate constructor
        if api_client is None: self.value = type_(value_data) if value_data is not None else None
        else: self.value = type_(value_data, api_client)

    def __repr__(self):
        return f"{self.__class__.__name__}({self.name}: {self.type_.__name__} = {self.value} {self.metadata})" 