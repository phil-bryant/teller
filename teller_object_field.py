from plum import dispatch
from teller_api_client_type import TellerAPIClient

class TellerObjectField:
    _primitive_attrs = {'name', 'type_'}
    
    @dispatch
    def __init__(self, name: str, type_: type, api_data: dict, metadata: dict, api_client: TellerAPIClient):
        api_name = metadata.get("api_name", name)
        super().__setattr__("name", name)
        super().__setattr__("type_", type_)
        super().__setattr__("metadata", metadata)
        super().__setattr__("api_name", api_name)
        super().__setattr__("value", type_(api_data[api_name], api_client))

    @dispatch
    def __init__(self, name: str, type_: type, api_data: None, metadata: dict, api_client: TellerAPIClient):
        api_name = metadata.get("api_name", name)
        super().__setattr__("name", name)
        super().__setattr__("type_", type_)
        super().__setattr__("metadata", metadata)
        super().__setattr__("api_name", api_name)
        super().__setattr__("value", None)

    @dispatch
    def __init__(self, name: str, type_: type, api_data: str, metadata: dict, api_client: None):
        api_name = metadata.get("api_name", name)
        super().__setattr__("name", name)
        super().__setattr__("type_", type_)
        super().__setattr__("metadata", metadata)
        super().__setattr__("api_name", api_name)
        super().__setattr__("value", api_data)

    @dispatch
    def __init__(self, name: str, type_: type, api_data: dict, metadata: dict, api_client: None):
        api_name = metadata.get("api_name", name)
        super().__setattr__("name", name)
        super().__setattr__("type_", type_)
        super().__setattr__("metadata", metadata)
        super().__setattr__("api_name", api_name)
        super().__setattr__("value", type_(api_data[api_name]))


    @dispatch
    def __init__(self, name: str, type_: type, api_data: None, metadata: dict, api_client: None):
        api_name = metadata.get("api_name", name)
        super().__setattr__("name", name)
        super().__setattr__("type_", type_)
        super().__setattr__("metadata", metadata)
        super().__setattr__("api_name", api_name)
        super().__setattr__("value", None)

    @dispatch
    def __init__(self, name: str, type_: type, api_data: dict):
        super().__setattr__("name", name)
        super().__setattr__("type_", type_)
        super().__setattr__("metadata", {})
        super().__setattr__("api_name", name)
        super().__setattr__("value", type_(api_data[name]))

    @dispatch
    def __init__(self, name: str, type_: type, api_data: dict, metadata: dict):
        api_name = metadata.get("api_name", name)
        super().__setattr__("name", name)
        super().__setattr__("type_", type_)
        super().__setattr__("metadata", metadata)
        super().__setattr__("api_name", api_name)
        super().__setattr__("value", type_(api_data[api_name]))

    @dispatch
    def __init__(self, name: str, type_: type, api_data: None, metadata: dict):
        api_name = metadata.get("api_name", name)
        super().__setattr__("name", name)
        super().__setattr__("type_", type_)
        super().__setattr__("metadata", metadata)
        super().__setattr__("api_name", api_name)
        super().__setattr__("value", None)
    
    def __setattr__(self, name: str, value: object) -> None:
        if name in TellerObjectField._primitive_attrs:  
            super().__setattr__(name, value)
        elif name == "metadata":
            super().__setattr__(name, value or {})
        elif name == "value":
            super().__setattr__(name, self.type_(value))

    def __getattr__(self, attribute_name: str) -> object:
        return self.metadata.get(attribute_name)
    
    ## def __repr__(self):
    ##    return f"{self.__class__.__name__}({self.name}: {self.type_.__name__} = {self.value} {self.metadata})" 