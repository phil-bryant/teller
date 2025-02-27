from plum import dispatch
from teller_api_client_type import TellerAPIClient

class TellerObjectField:
    _primitive_attrs = {'name', 'type_'}
    
    def _initialize_common(self, name, type_, metadata=None):
        metadata = metadata or {}
        api_name = metadata.get("api_name", name)
        super().__setattr__("name", name)
        super().__setattr__("type_", type_)
        super().__setattr__("metadata", metadata)
        super().__setattr__("api_name", api_name)
        return api_name

    @dispatch
    def __init__(self, name: str, type_: type, api_data: dict, metadata: dict, api_client: TellerAPIClient):
        api_name = self._initialize_common(name, type_, metadata)
        super().__setattr__("value", type_(api_data[api_name], api_client))

    @dispatch
    def __init__(self, name: str, type_: type, api_data: None, metadata: dict, api_client: TellerAPIClient):
        self._initialize_common(name, type_, metadata)
        super().__setattr__("value", None)

    @dispatch
    def __init__(self, name: str, type_: type, api_data: str, metadata: dict, api_client: None):
        self._initialize_common(name, type_, metadata)
        super().__setattr__("value", api_data)

    @dispatch
    def __init__(self, name: str, type_: type, api_data: dict, metadata: dict, api_client: None):
        api_name = self._initialize_common(name, type_, metadata)
        super().__setattr__("value", type_(api_data[api_name]))

    @dispatch
    def __init__(self, name: str, type_: type, api_data: None, metadata: dict, api_client: None):
        self._initialize_common(name, type_, metadata)
        super().__setattr__("value", None)

    @dispatch
    def __init__(self, name: str, type_: type, api_data: dict):
        api_name = self._initialize_common(name, type_)
        super().__setattr__("value", type_(api_data[api_name]))

    @dispatch
    def __init__(self, name: str, type_: type, api_data: dict, metadata: dict):
        api_name = self._initialize_common(name, type_, metadata)
        super().__setattr__("value", type_(api_data[api_name]))

    @dispatch
    def __init__(self, name: str, type_: type, api_data: None, metadata: dict):
        self._initialize_common(name, type_, metadata)
        super().__setattr__("value", None)
    
    def __setattr__(self, name: str, value: object) -> None:
        if name in TellerObjectField._primitive_attrs:  
            super().__setattr__(name, value)
        elif name == "metadata":
            super().__setattr__(name, value or {})
        elif name == "value":
            if isinstance(value, list):
                super().__setattr__(name, value)
            else:
                super().__setattr__(name, self.type_(value))

    def __getattr__(self, attribute_name: str) -> object:
        # Access metadata via __dict__ to avoid recursion
        metadata = self.__dict__.get("metadata", {})
        return metadata.get(attribute_name)
    
    def __repr__(self):
        return f"{self.__class__.__name__}({self.name}: {self.type_.__name__} = {self.value} {self.metadata})" 