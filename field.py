from typing import Any, Type

class Field:
    _primitive_attrs = {'name', 'type_'}
    
    def __init__(self, name: str, type_: Type, value: Any = None, metadata: dict = None):
        super().__setattr__("name", name)
        super().__setattr__("type_", type_)
        super().__setattr__("value", type_(value))
        super().__setattr__("metadata", metadata or {})
    
    def __setattr__(self, name: str, value: Any) -> None:
        if name in Field._primitive_attrs:  
            super().__setattr__(name, value)
        elif name is "metadata":
            self.metadata[name] = value  
        elif name is "value":
            super().__setattr__(name, self.type_(value))

    def __getattr__(self, attribute_name: str) -> Any:
        return self.metadata.get(attribute_name)
    
    def __repr__(self):
        return f"{self.__class__.__name__}({self.name}: {self.type_.__name__} = {self.value} {self.metadata})"
